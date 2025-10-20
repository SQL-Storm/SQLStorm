-- {"query": "73.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 882} 
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '90 days'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
Qualified AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    ra.Reputation,
    ra.OwnerDisplayName,
    ra.Score,
    ra.ViewCount,
    ra.CommentCount,
    ra.AnswerCount,
    ra.FavoriteCount,
    ra.PostTypeId,
    ra rn
  FROM RecentActive ra
  WHERE ra.rn <= 5
),
Correlation AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.LastActivityDate,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.Reputation,
    q.Score,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.PostTypeId,
    -- correlated subquery: number of comments by the post's author on posts with similar tags
    (
      SELECT COUNT(*) 
      FROM Comments c
      JOIN Posts p2 ON c.PostId = p2.Id
      WHERE p2.OwnerUserId = q.OwnerUserId
        AND p2.LastActivityDate >= q.CreationDate
        AND (POSITION(lower(TRIM(tag)) IN lower(UNNEST(string_to_array(lower(q.Tags), '>')))) > 0 OR c.Text IS NOT NULL)
    ) AS AuthorActivitySimilarlyTagged
  FROM Qualified q
),
Windowed AS (
  SELECT
    *,
    SUM(COALESCE(AuthorActivitySimilarlyTagged,0)) OVER (PARTITION BY PostTypeId ORDER BY LastActivityDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeSimilarAuthorActivity
  FROM Correlation
),
Aggregated AS (
  SELECT
    PostId,
    Title,
    Tags,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    OwnerDisplayName,
    Reputation,
    Score,
    ViewCount,
    CommentCount,
    AnswerCount,
    FavoriteCount,
    PostTypeId,
    AuthorActivitySimilarlyTagged,
    CumulativeSimilarAuthorActivity
  FROM Windowed
  ORDER BY LastActivityDate DESC
  FETCH FIRST 100 ROWS ONLY
)
SELECT
  a.PostId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.LastActivityDate,
  a.OwnerDisplayName,
  a.Reputation,
  a.Score,
  a.ViewCount,
  a.CommentCount,
  a.AnswerCount,
  a.FavoriteCount,
  a.PostTypeId,
  a.AuthorActivitySimilarTagged,
  a.CumulativeSimilarAuthorActivity,
  -- additional complex expression: ratio of views to score, with NULL-safe handling
  CASE WHEN a.Score = 0 THEN NULL ELSE (a.ViewCount::float / a.Score) END AS ViewsPerScore
FROM Aggregated a
WHERE a.CumulativeSimilarAuthorActivity > 0
  AND EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = a.PostId
      AND pl.LinkTypeId IN (1,3)
  )
  AND NOT EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = a.PostId
      AND v.VoteTypeId = 10 -- deletion votes should exclude
  )
ORDER BY a.LastActivityDate DESC, a.ViewCount DESC;