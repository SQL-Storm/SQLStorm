-- {"query": "156.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1936} 
WITH user_base AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS total_posts,
         (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS avg_post_score,
         (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS last_post_date
  FROM Users u
),
activity AS (
  SELECT v.UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_cast,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_cast,
         COUNT(*) AS total_votes_cast
  FROM Votes v
  GROUP BY v.UserId
),
recent AS (
  SELECT u.Id,
         MAX(COALESCE(p.LastEditDate, p.CreationDate)) AS recent_post_activity
  FROM Posts p
  RIGHT JOIN Users u ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
badges AS (
  SELECT b.UserId, STRING_AGG(b.Name, ',') AS badge_list
  FROM Badges b
  GROUP BY b.UserId
)
SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       bu.total_posts,
       bu.avg_post_score,
       bu.last_post_date,
       a.upvotes_cast,
       a.downvotes_cast,
       a.total_votes_cast,
       r.recent_post_activity,
       ba.badge_list
FROM Users u
LEFT JOIN user_base bu ON bu.Id = u.Id
LEFT JOIN activity a ON a.UserId = u.Id
LEFT JOIN recent r ON r.Id = u.Id
LEFT JOIN badges ba ON ba.UserId = u.Id
ORDER BY u.Reputation DESC
LIMIT 200;