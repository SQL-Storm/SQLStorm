-- {"query": "56019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 282} 
WITH top_100_users AS (
  SELECT Id, Reputation, DisplayName
  FROM Users
  ORDER BY Reputation DESC
  LIMIT 100
),
user_badges AS (
  SELECT u.Id, COUNT(b.Id) AS badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
user_posts AS (
  SELECT u.Id, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id
),
user_votes AS (
  SELECT u.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  GROUP BY u.Id
)
SELECT 
  u.Id,
  u.Reputation,
  u.DisplayName,
  ub.badge_count,
  up.post_count,
  uv.upvotes,
  uv.downvotes
FROM top_100_users u
JOIN user_badges ub ON u.Id = ub.Id
JOIN user_posts up ON u.Id = up.Id
JOIN user_votes uv ON u.Id = uv.Id
ORDER BY u.Reputation DESC;