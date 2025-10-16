WITH top_tags AS (
  SELECT 
    T.TagName, 
    SUM(CASE WHEN P.Score > 0 THEN 1 ELSE 0 END) AS positive_posts,
    SUM(CASE WHEN P.Score < 0 THEN 1 ELSE 0 END) AS negative_posts,
    COUNT(DISTINCT P.Id) AS total_posts
  FROM 
    Tags T
  JOIN 
    Posts P ON P.Id = T.ExcerptPostId OR P.Id = T.WikiPostId
  GROUP BY 
    T.TagName
  HAVING 
    COUNT(DISTINCT P.Id) > 100
),
top_users AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    SUM(CASE WHEN P.Score > 0 THEN 1 ELSE 0 END) AS positive_posts,
    SUM(CASE WHEN P.Score < 0 THEN 1 ELSE 0 END) AS negative_posts,
    COUNT(DISTINCT P.Id) AS total_posts
  FROM 
    Users U
  JOIN 
    Posts P ON P.OwnerUserId = U.Id
  GROUP BY 
    U.Id, U.DisplayName
  HAVING 
    COUNT(DISTINCT P.Id) > 50
),
tag_user_score AS (
  SELECT 
    T.TagName, 
    U.DisplayName, 
    SUM(P.Score) AS total_score
  FROM 
    Tags T
  JOIN 
    Posts P ON P.Id = T.ExcerptPostId OR P.Id = T.WikiPostId
  JOIN 
    Users U ON P.OwnerUserId = U.Id
  GROUP BY 
    T.TagName, U.DisplayName
)
SELECT 
  TTS.TagName, 
  TUS.DisplayName, 
  TUS.positive_posts, 
  TUS.negative_posts, 
  TUS.total_posts, 
  (TUS.positive_posts * 1.0) / NULLIF(TUS.total_posts, 0) AS positive_rate,
  (TTS.positive_posts * 1.0) / NULLIF(TTS.total_posts, 0) AS tag_positive_rate,
  TU.total_score
FROM 
  top_tags TTS
JOIN 
  top_users TUS ON TRUE
JOIN 
  tag_user_score TU ON TU.TagName = TTS.TagName AND TU.DisplayName = TUS.DisplayName
WHERE 
  TUS.total_posts > 50
  AND TUS.positive_posts > 10 
  AND TTS.positive_posts > 50
GROUP BY
  TTS.TagName,
  TUS.DisplayName,
  TUS.positive_posts,
  TUS.negative_posts,
  TUS.total_posts,
  TTS.positive_posts,
  TTS.total_posts,
  TU.total_score
ORDER BY 
  TU.total_score DESC,
  positive_rate DESC;