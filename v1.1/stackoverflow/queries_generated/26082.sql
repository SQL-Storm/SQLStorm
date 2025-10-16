-- {"query": "26082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 496} 

WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS score_rank,
         ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS view_rank
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
),
post_links AS (
  SELECT pl.PostId, pl.RelatedPostId, lt.Name AS link_type
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
votes AS (
  SELECT v.PostId, v.VoteTypeId, vt.Name AS vote_type
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE vt.Name IN ('UpMod', 'DownMod')
)
SELECT 
  tu.DisplayName AS top_user,
  tp.Title AS top_post,
  tp.Score AS post_score,
  tp.ViewCount AS post_views,
  pl.link_type AS post_link_type,
  v.vote_type AS post_vote_type,
  COUNT(DISTINCT pl.RelatedPostId) AS related_posts,
  SUM(CASE WHEN v.vote_type = 'UpMod' THEN 1 ELSE 0 END) AS up_votes,
  SUM(CASE WHEN v.vote_type = 'DownMod' THEN 1 ELSE 0 END) AS down_votes,
  tp.score_rank AS score_rank,
  tp.view_rank AS view_rank
FROM top_users tu
JOIN top_posts tp ON tu.Id = tp.OwnerUserId
LEFT JOIN post_links pl ON tp.Id = pl.PostId
LEFT JOIN votes v ON tp.Id = v.PostId
GROUP BY 
  tu.DisplayName,
  tp.Title,
  tp.Score,
  tp.ViewCount,
  pl.link_type,
  v.vote_type,
  tp.score_rank,
  tp.view_rank
ORDER BY 
  related_posts DESC,
  up_votes DESC,
  down_votes ASC;
