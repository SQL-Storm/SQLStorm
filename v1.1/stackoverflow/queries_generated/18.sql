-- {"query": "18.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 243} 
WITH ranked_users AS (
  SELECT Id, DisplayName, Reputation,
         ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
  FROM Users
),
top_badge_users AS (
  SELECT u.Id, u.DisplayName, r.rank, b.Name AS BadgeName
  FROM ranked_users r
  JOIN Badges ba ON r.Id = ba.UserId
  JOIN Users u ON r.Id = u.Id
  WHERE ba.Class = 1 -- Gold badge
  AND ba.TagBased = 0 -- Named badge
),
post_activity AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(DISTINCT p.Id) AS NumPosts,
         COUNT(DISTINCT c.Id) AS NumComments,
         SUM(v.VoteTypeId) AS TotalVotes
  FROM Posts p
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
)
SELECT tbu.DisplayName, tbu.rank, pa.NumPosts, pa.NumComments, pa.TotalVotes
FROM top_badge_users tbu
LEFT JOIN post_activity pa ON tbu.Id = pa.UserId
ORDER BY tbu.rank DESC;