WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN Posts p ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
),
posts_by_tag AS (
  SELECT tt.TagName, p.Id
  FROM top_tags tt
  JOIN Posts p ON POSITION('<' || tt.TagName || '>' IN p.Tags) > 0
)
SELECT 
  tu.DisplayName, 
  tu.post_count, 
  pt.TagName, 
  COUNT(v.Id) AS vote_count
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN Votes v ON p.Id = v.PostId
JOIN posts_by_tag pt ON p.Id = pt.Id
WHERE v.VoteTypeId = 2 AND p.PostTypeId = 1 AND p.Score > 10
GROUP BY tu.DisplayName, tu.post_count, pt.TagName
ORDER BY vote_count DESC;