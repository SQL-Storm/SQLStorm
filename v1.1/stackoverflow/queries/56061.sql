WITH top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
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
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.Tags
  FROM Posts p
  JOIN top_tags tt ON p.Tags LIKE '%' || tt.TagName || '%'
  WHERE p.PostTypeId = 1
  ORDER BY p.Score DESC, p.ViewCount DESC
  LIMIT 10
),
top_badges AS (
  SELECT b.Name, COUNT(b.UserId) AS user_count, b.UserId
  FROM Badges b
  JOIN top_users tu ON b.UserId = tu.Id
  GROUP BY b.Name, b.UserId
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
JOIN top_users tu ON tt.post_count > 50 AND tu.post_count > 50
JOIN top_posts tp ON tt.post_count > 50 AND tp.Score > 50
JOIN top_badges tb ON tu.post_count > 50 AND tb.user_count > 5
ORDER BY tt.post_count DESC, tu.post_count DESC, tp.Score DESC, tb.user_count DESC;