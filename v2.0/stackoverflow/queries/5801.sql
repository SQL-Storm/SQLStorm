-- {"query": "5801.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 726}
WITH RankedTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
    AND p.ClosedDate IS NULL
),
ActiveTagUsage AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  GROUP BY t.TagName
),
ComplexMetrics AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.AnswerCount,
    rp.Tags,
    rp.LastActivityDate,
    CASE
      WHEN rp.Score > 0 THEN 'positive'
      WHEN rp.Score < 0 THEN 'negative'
      ELSE 'neutral'
    END AS ScoreCategory,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.CreationDate > rp.CreationDate) AS NewCommentsSinceCreation,
    FIRST_VALUE(u.DisplayName) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS OwnerFirstDisplayName
  FROM RankedTopPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  WHERE rp.rn <= 50
)
SELECT
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.OwnerUserId,
  cm.ViewCount,
  cm.Score,
  cm.CommentCount,
  cm.AnswerCount,
  cm.Tags,
  cm.LastActivityDate,
  cm.ScoreCategory,
  cm.NewCommentsSinceCreation,
  cm.OwnerFirstDisplayName,
  a.TotalViews AS OwnerTotalViews,
  a.AvgScore AS OwnerAvgScore,
  a.TagCount
FROM ComplexMetrics cm
LEFT JOIN (
  SELECT
    u.Id AS UserId,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT t.TagName) AS TagCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  GROUP BY u.Id
) a ON cm.OwnerUserId = a.UserId
LEFT JOIN ActiveTagUsage a2 ON a2.TagName = TRIM(BOTH '>< ' FROM REPLACE(REPLACE(cm.Tags, '<', ''), '>', ''))
GROUP BY
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.OwnerUserId,
  cm.ViewCount,
  cm.Score,
  cm.CommentCount,
  cm.AnswerCount,
  cm.Tags,
  cm.LastActivityDate,
  cm.ScoreCategory,
  cm.NewCommentsSinceCreation,
  cm.OwnerFirstDisplayName,
  a.TotalViews,
  a.AvgScore,
  a.TagCount,
  a2.TagName
ORDER BY cm.CreationDate DESC
LIMIT 100;