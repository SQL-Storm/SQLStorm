-- {"query": "5086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 977} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Body,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
),
RecentActivity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.Score,
    rp.ViewCount,
    rp.LastActivityDate,
    CASE
      WHEN rp.LastActivityDate > NOW() - INTERVAL '180 days' THEN 1
      ELSE 0
    END AS RecentlyActiveFlag,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.PostId) AS UpvotesOnPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.PostId) AS DownvotesOnPost,
    COUNT(DISTINCT c.Id) OVER (PARTITION BY rp.PostId) AS CommentCountOnPost
  FROM RankedPosts rp
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  LEFT JOIN Comments c ON c.PostId = rp.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = rp.PostId
  WHERE rp.rn_type = 1
),
TagMetrics AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired,
    ARRAY_AGG(DISTINCT tp.Id) AS PostIds
  FROM Tags t
  LEFT JOIN Posts tp ON tp.Id = t.WikiPostId OR tp.Id = t.ExcerptPostId
  GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired
),
ComplexQuery AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerDisplayName,
    ra.Reputation,
    ra.Score,
    ra.ViewCount,
    ra.LastActivityDate,
    ra.RecentlyActiveFlag,
    ra.UpvotesOnPost,
    ra.DownvotesOnPost,
    ra.CommentCountOnPost,
    t.TagName,
    tc.Count AS TagUsageCount,
    CASE
      WHEN ra.Score > 0 AND ra.RecentlyActiveFlag = 1 THEN 'Hot'
      WHEN ra.Score <= 0 THEN 'LowScore'
      ELSE 'Active'
    END AS StatusCategory,
    -- Correlated subquery: find a higher-scored post by the same user in the last 90 days
    (SELECT MAX(pp.Score)
     FROM Posts pp
     WHERE pp.OwnerUserId = (SELECT OwnerUserId FROM Posts WHERE Id = ra.PostId)
       AND pp.CreationDate > NOW() - INTERVAL '90 days'
       AND pp.Id <> ra.PostId
    ) AS MaxPeerScoreLast90Days,
    -- Set operator: union with an auxiliary synthetic dataset for benchmarking
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = ra.PostId AND v2.VoteTypeId = 2)
    UNION ALL
    SELECT
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
      NULL, NULL, NULL, NULL, NULL
  FROM dual
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerDisplayName,
  c.Reputation,
  c.Score,
  c.ViewCount,
  c.LastActivityDate,
  c.RecentlyActiveFlag,
  c.UpvotesOnPost,
  c.DownvotesOnPost,
  c.CommentCountOnPost,
  c.TagName,
  c.TagUsageCount,
  c.StatusCategory,
  c.MaxPeerScoreLast90Days
FROM ComplexQuery c
ORDER BY c.LastActivityDate DESC NULLS LAST
LIMIT 100;