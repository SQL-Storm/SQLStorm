-- {"query": "5929.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 689} 
WITH RankedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    -- compute a dynamic popularity metric
    (CAST(p.ViewCount AS decimal(18,2)) * 0.3 +
     CAST(p.Score AS decimal(18,2)) * 2.0 +
     CAST(p.AnswerCount AS decimal(18,2)) * 1.5 +
     COALESCE(CAST(vt.BountyAmount AS decimal(18,2)),0) * 0.0) AS Popularity
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes vt ON p.Id = vt.PostId AND vt.VoteTypeId = 8 -- BountyStart as proxy for engagement timing
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
Aggregated AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.OwnerDisplayName,
    rq.Reputation,
    rq.Views,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.Popularity,
    rq.CreationDate,
    rq.LastActivityDate,
    -- tag-based filtering: prefer posts with a tag from a dynamic set computed from Tags field
    CASE
      WHEN rq.Tags IS NOT NULL THEN
        (SELECT MAX(CASE WHEN t.TagName IN ('sql','performance','index','optimization') THEN 1 ELSE 0 END)
         FROM unnest(string_to_array(rq.Tags, '><')) AS t(TagName))
      ELSE 0
    END AS HasPreferredTag
  FROM RankedQuestions rq
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (
      ORDER BY a.Popularity DESC,
               a.LastActivityDate DESC,
               a.CreationDate ASC
    ) AS rn
  FROM Aggregated a
  WHERE a.HasPreferredTag = 1
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerDisplayName,
  w.Reputation,
  w.ViewCount AS Views,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.Popularity,
  w.CreationDate,
  w.LastActivityDate
FROM Windowed w
WHERE w.rn <= 100
UNION ALL
SELECT
  w.PostId,
  w.Title,
  w.OwnerDisplayName,
  w.Reputation,
  w.ViewCount AS Views,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.Popularity,
  w.CreationDate,
  w.LastActivityDate
FROM Windowed w
WHERE w.rn > 100 AND w.Popularity > 0
ORDER BY Popularity DESC, LastActivityDate DESC
LIMIT 200;