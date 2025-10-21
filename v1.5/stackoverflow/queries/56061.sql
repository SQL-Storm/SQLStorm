WITH top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON CAST(',' || p.Tags || ',' AS TEXT) LIKE '%,' || t.TagName || ',%'
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
),
top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount
  FROM Posts p
  JOIN top_tags tt ON CAST(',' || p.Tags || ',' AS TEXT) LIKE '%,' || tt.TagName || ',%'
  WHERE p.PostTypeId = 1
  ORDER BY p.Score DESC, p.ViewCount DESC
  LIMIT 10
),
top_badges AS (
  SELECT b.Name, COUNT(b.UserId) AS user_count
  FROM Badges b
  JOIN top_users tu ON b.UserId = tu.Id
  GROUP BY b.Name
  ORDER BY user_count DESC
  LIMIT 10
)
SELECT 
  tt.TagName, 
  tu.DisplayName, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount, 
  tb.Name
FROM top_tags tt
JOIN top_users tu ON TRUE
JOIN top_posts tp ON TRUE
JOIN top_badges tb ON TRUE
ORDER BY tt.post_count DESC, tu.post_count DESC, tp.Score DESC, tb.user_count DESC;