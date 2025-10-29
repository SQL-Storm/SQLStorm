-- {"query": "5179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 966}
WITH
SelectedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.Body,
    p.LastEditDate,
    p.LastEditorUserId,
    p.OwnerDisplayName,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
TopCategories AS (
  SELECT
    t.TagName,
    t.Count
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
RankedQuestions AS (
  SELECT
    sp.PostId,
    sp.Title,
    sp.Tags,
    sp.CreationDate,
    sp.LastActivityDate,
    sp.Score,
    sp.ViewCount,
    sp.AnswerCount,
    sp.CommentCount,
    sp.FavoriteCount,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(NULLIF(TRIM(BOTH ' ' FROM COALESCE(u.DisplayName, sp.OwnerDisplayName)), ''), '')
      ORDER BY sp.Score DESC, sp.ViewCount DESC, sp.LastActivityDate DESC
    ) AS rn,
    sp.OwnerUserId
  FROM SelectedPosts sp
  LEFT JOIN Users u ON sp.OwnerUserId = u.Id
  LEFT JOIN Posts p ON sp.PostId = p.Id
  WHERE sp.Title ILIKE '%' || 'benchmark' || '%'
     OR sp.Tags ILIKE '%' || 'benchmark' || '%'
),
WindowAgg AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.rn,
    SUM(
      CASE
        WHEN v.VoteTypeId = 2 THEN 1
        WHEN v.VoteTypeId = 3 THEN -1
        ELSE 0
      END
    ) OVER (
      PARTITION BY rq.PostId
      ORDER BY v.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS NetVotes,
    rq.OwnerUserId
  FROM RankedQuestions rq
  LEFT JOIN Votes v ON v.PostId = rq.PostId
  LEFT JOIN Users u ON rq.OwnerUserId = u.Id
  WHERE rq.rn = 1
),
CorrelatedMetrics AS (
  SELECT
    wa.PostId,
    wa.Title,
    wa.Tags,
    wa.CreationDate,
    wa.LastActivityDate,
    wa.Score,
    wa.ViewCount,
    wa.AnswerCount,
    wa.CommentCount,
    wa.FavoriteCount,
    wa.NetVotes,
    wa.OwnerUserId,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = wa.PostId AND v2.BountyAmount IS NOT NULL) AS AvgBounty,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = wa.PostId) AS LinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = wa.PostId) AS CommentCountAll
  FROM WindowAgg wa
)
SELECT
  cm.PostId,
  cm.Title,
  cm.Tags,
  cm.CreationDate,
  cm.LastActivityDate,
  cm.Score,
  cm.ViewCount,
  cm.AnswerCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.NetVotes,
  cm.AvgBounty,
  cm.LinkCount,
  cm.CommentCountAll,
  MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS GoldBadgeDate,
  MAX(CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadgeName,
  MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS SilverBadgeDate,
  MAX(CASE WHEN b.Class = 2 THEN b.Name END) AS SilverBadgeName
FROM CorrelatedMetrics cm
LEFT JOIN Badges b ON b.UserId = cm.OwnerUserId
GROUP BY
  cm.PostId,
  cm.Title,
  cm.Tags,
  cm.CreationDate,
  cm.LastActivityDate,
  cm.Score,
  cm.ViewCount,
  cm.AnswerCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.NetVotes,
  cm.AvgBounty,
  cm.LinkCount,
  cm.CommentCountAll,
  cm.OwnerUserId
ORDER BY cm.Score DESC, cm.NetVotes DESC, cm.LastActivityDate DESC
LIMIT 100;