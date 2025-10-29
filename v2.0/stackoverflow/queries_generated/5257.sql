-- {"query": "5257.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 882} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    COALESCE(u.Reputation, 0) AS UserReputation,
    COALESCE(a.DisplayName, p.OwnerDisplayName) AS PostOwnerName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users a ON p.LastEditorUserId = a.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
recent_actions AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Comment,
    ph.Text,
    ph.RevisionGUID,
    ph.PostNoticeId,
    ph.VotedForCloseReason := NULL,
    ph.ContentLicense
  FROM PostHistory ph
  WHERE ph.CreationDate >= NOW() - INTERVAL '180 days'
    AND ph.PostHistoryTypeId IN (10, 11, 16, 24, 52, 53) -- close, reopen, community owned, suggested edit, hot question moves
),
tag_aggregates AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.Count > 0
),
complex_filter AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.UserReputation,
    RP.PostOwnerName,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ContentLicense,
    rz.AverageTagRelevance
  FROM ranked_posts rp
  LEFT JOIN (
    SELECT
      t.TagName,
      AVG(COALESCE(v.BountyAmount, 0)) AS AverageTagRelevance
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.WikiPostId
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName
  ) AS rz ON rz.TagName = SUBSTRING_INDEX(SUBSTRING_INDEX(rp.Tags, '><', 1), '<', -1)
  WHERE rp rn_owner = 1
    AND rp.Score > 0
    AND rp.ViewCount > 100
)
SELECT
  cp.PostId,
  cp.Title,
  cp.Tags,
  cp.CreationDate,
  cp.Score,
  cp.ViewCount,
  cp.UserReputation,
  cp.PostOwnerName,
  cp.LastActivityDate,
  cp.PostTypeId,
  cp.ParentId,
  cp.AcceptedAnswerId,
  cp.CommentCount,
  cp.FavoriteCount,
  cp.Body,
  cp.ContentLicense,
  COALESCE((SELECT STRING_AGG(tag.TagName, ',') FROM unnest(string_to_array(cp.Tags, '><')) AS tag), '') AS TagList,
  CASE
    WHEN cp.PostTypeId = 1 THEN 'Question'
    WHEN cp.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind
FROM complex_filter cp
LEFT JOIN LATERAL (
  SELECT AVG(v.BountyAmount) AS AverageBounty
  FROM Votes v
  WHERE v.PostId = cp.PostId
) AS av ON TRUE
ORDER BY cp.LastActivityDate DESC
LIMIT 100;