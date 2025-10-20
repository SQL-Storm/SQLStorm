-- {"query": "26010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 582} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY post_count DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) AS post_count
  FROM Tags t
  JOIN PostLinks pl ON t.Id = pl.RelatedPostId
  JOIN Posts p ON pl.PostId = p.Id
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
),
recent_posts AS (
  SELECT p.Id, p.Title, p.CreationDate, u.DisplayName AS owner
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 week'
),
user_badges AS (
  SELECT u.Id, COUNT(b.Id) AS badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
question_answers AS (
  SELECT p.Id, COUNT(a.Id) AS answer_count
  FROM Posts p
  JOIN Posts a ON p.Id = a.ParentId
  WHERE p.PostTypeId = 1 AND a.PostTypeId = 2
  GROUP BY p.Id
)
SELECT 
  u.Id,
  u.DisplayName,
  u.Reputation,
  tu.post_count,
  tt.TagName,
  rp.Title,
  rp.CreationDate,
  ub.badge_count,
  qa.answer_count,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  ph.Comment,
  v.VoteTypeId
FROM Users u
JOIN top_users tu ON u.Id = tu.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostHistory ph ON p.Id = ph.PostId
JOIN Votes v ON p.Id = v.PostId
JOIN recent_posts rp ON p.Id = rp.Id
JOIN user_badges ub ON u.Id = ub.Id
JOIN question_answers qa ON p.Id = qa.Id
JOIN PostLinks pl ON p.Id = pl.PostId
JOIN Tags t ON pl.RelatedPostId = t.Id
JOIN top_tags tt ON t.TagName = tt.TagName
WHERE p.PostTypeId = 1 AND v.VoteTypeId = 2
AND u.Reputation > 1000 AND tu.post_count > 10
AND tt.post_count > 50 AND ub.badge_count > 5
AND qa.answer_count > 2 AND p.Score > 10
AND p.ViewCount > 100 AND p.CommentCount > 5
ORDER BY u.Reputation DESC, tu.post_count DESC, tt.post_count DESC;