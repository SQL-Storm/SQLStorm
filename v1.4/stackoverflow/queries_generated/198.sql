-- {"query": "198.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2041} 
WITH base_posts AS (
  SELECT Id, OwnerUserId, Score, CreationDate, LastActivityDate, PostTypeId, Tags, Title, Body, ViewCount
  FROM Posts
),
user_meta AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT b.Id) AS badge_count,
         MAX(p.LastActivityDate) AS last_active
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN base_posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
score_by_user AS (
  SELECT OwnerUserId, SUM(Score) AS total_score
  FROM Posts
  GROUP BY OwnerUserId
),
enhanced AS (
  SELECT um.UserId,
         um.DisplayName,
         um.Reputation,
         um.badge_count,
         um.last_active,
         COALESCE(sbu.total_score, 0) AS total_score,
         ROW_NUMBER() OVER (PARTITION BY um.UserId ORDER BY um.last_active DESC NULLS LAST) AS rn
  FROM user_meta um
  LEFT JOIN score_by_user sbu ON sbu.OwnerUserId = um.UserId
),
set_ops AS (
  -- first branch: high-scoring users
  SELECT UserId, DisplayName, Reputation, badge_count, last_active, total_score
  FROM enhanced
  WHERE total_score > 1000

  UNION ALL

  -- second branch: rest of users, with a harmless calculation to exercise expressions
  SELECT UserId, DisplayName, Reputation, badge_count, last_active, total_score
  FROM enhanced
  WHERE total_score <= 1000
)
SELECT
  s.UserId,
  s.DisplayName,
  s.Reputation,
  s.badge_count,
  s.last_active,
  s.total_score,
  (SELECT ROUND(AVG(LENGTH(p.Body))::numeric, 2)
   FROM Posts p
   WHERE p.OwnerUserId = s.UserId) AS avg_body_length,
  (SELECT COUNT(*) 
   FROM PostLinks pl
   JOIN Posts orp ON pl.RelatedPostId = orp.Id
   WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = s.UserId)
     AND pl.LinkTypeId = 1) AS linked_post_count,
  (CASE
     WHEN s.Reputation IS NULL THEN NULL
     WHEN s.Reputation > 5000 THEN true
     ELSE false
   END) AS is_veteran
FROM set_ops s
ORDER BY s.total_score DESC NULLS LAST, s.Reputation DESC NULLS LAST
LIMIT 100;