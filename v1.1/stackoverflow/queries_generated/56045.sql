-- {"query": "56045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 296} 

WITH top_users AS (
  SELECT u.Id, u.DisplayName, SUM(v.BountyAmount) AS total_bounty
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  WHERE v.VoteTypeId = 8
  GROUP BY u.Id, u.DisplayName
  ORDER BY total_bounty DESC
  LIMIT 10
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount
  FROM Posts p
  JOIN PostLinks pl ON p.Id = pl.PostId
  WHERE pl.LinkTypeId = 1
  GROUP BY p.Id, p.Title, p.Score, p.ViewCount
  ORDER BY p.Score DESC
  LIMIT 10
),
post_history_stats AS (
  SELECT ph.PostId, COUNT(ph.Id) AS revision_count
  FROM PostHistory ph
  GROUP BY ph.PostId
)
SELECT 
  tu.DisplayName AS top_user, 
  tp.Title AS top_post, 
  phs.revision_count, 
  SUM(v.BountyAmount) AS total_bounty
FROM top_users tu
JOIN Votes v ON tu.Id = v.UserId
JOIN top_posts tp ON v.PostId = tp.Id
JOIN post_history_stats phs ON tp.Id = phs.PostId
WHERE v.VoteTypeId = 8
GROUP BY tu.DisplayName, tp.Title, phs.revision_count
ORDER BY total_bounty DESC;
