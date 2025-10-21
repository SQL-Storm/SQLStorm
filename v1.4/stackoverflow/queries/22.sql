-- {"query": "22.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 704} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.PostTypeId,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.ContentLicense,
    COALESCE(a.Reputation, 0) AS OwnerReputation,
    STRING_AGG(DISTINCT vt.Name, ',') AS VoteTypesApplied,
    COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS PostsByOwner
  FROM Posts p
  LEFT JOIN Users a ON a.Id = p.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY
    p.Id, p.Title, p.Body, p.CreationDate, p.Score, p.ViewCount, p.Tags,
    p.OwnerUserId, p.OwnerDisplayName, p.LastActivityDate, p.CommentCount,
    p.AnswerCount, p.FavoriteCount, p.ParentId, p.PostTypeId, p.LastEditorUserId,
    p.LastEditorDisplayName, p.LastEditDate, p.ContentLicense, a.Reputation
),
WindowStats AS (
  SELECT
    tp.*,
    ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.CreationDate DESC) AS rn_by_owner,
    MAX(tp.Score) OVER () AS GlobalMaxScore,
    AVG(tp.ViewCount) OVER () AS GlobalAvgViews
  FROM TopPosts tp
),
Filtered AS (
  SELECT *
  FROM WindowStats
  WHERE rn_by_owner = 1
),
ComplexCalc AS (
  SELECT
    f.*,
    (f.Score * CASE WHEN f.ViewCount > 0 THEN 1 ELSE 0 END)
      + (CASE WHEN f.CommentCount IS NULL THEN 0 ELSE f.CommentCount END) AS EngagementScore,
    (CASE WHEN f.OwnerReputation > 1000 THEN 1 ELSE 0 END) AS HighRepOwner,
    (ARRAY_LENGTH(STRING_TO_ARRAY(f.Tags, '>'), 1) > 0) AS HasTags
  FROM Filtered f
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.Tags,
  c.EngagementScore,
  c.HighRepOwner,
  c.HasTags,
  c.GlobalMaxScore,
  c.GlobalAvgViews,
  c.PostTypeId,
  c.ParentId,
  c.LastEditDate,
  c.ContentLicense
FROM ComplexCalc c
LEFT JOIN (SELECT MAX(Score) AS GlobalMaxScore FROM TopPosts) g
  ON 1=1
LEFT JOIN (SELECT AVG(ViewCount) AS GlobalAvgViews FROM TopPosts) v
  ON 1=1
ORDER BY c.CreationDate DESC
LIMIT 100;