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
    (CAST(p.ViewCount AS DECIMAL(18,2)) * 0.3 +
     CAST(p.Score AS DECIMAL(18,2)) * 2.0 +
     CAST(p.AnswerCount AS DECIMAL(18,2)) * 1.5 +
     COALESCE(CAST(vt.BountyAmount AS DECIMAL(18,2)),0) * 0.0) AS Popularity
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes vt ON p.Id = vt.PostId AND vt.VoteTypeId = 8
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
Aggregated AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.OwnerDisplayName,
    rq.Reputation,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CommentCount,
    rq.FavoriteCount,
    rq.Popularity,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Tags,
    CASE
      WHEN rq.Tags IS NOT NULL THEN
        (SELECT MAX(CASE WHEN t.TagName IN ('sql','performance','index','optimization') THEN 1 ELSE 0 END)
         FROM (
           -- split tag string like '<tag1><tag2>' into rows for portability
           SELECT TRIM(BOTH '<>' FROM value) AS TagName
           FROM (
             SELECT regexp_split_to_table(rq.Tags, '><') AS value
           ) s
         ) t)
      ELSE 0
    END AS HasPreferredTag
  FROM RankedQuestions rq
),
Windowed AS (
  SELECT
    a.PostId,
    a.Title,
    a.OwnerDisplayName,
    a.Reputation,
    a.ViewCount,
    a.AnswerCount,
    a.CommentCount,
    a.FavoriteCount,
    a.Popularity,
    a.CreationDate,
    a.LastActivityDate,
    a.Tags,
    a.HasPreferredTag,
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