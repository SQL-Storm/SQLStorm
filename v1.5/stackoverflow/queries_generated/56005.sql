-- {"query": "56005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 381} 

WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(b.Id) as badge_count
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY badge_count DESC
  LIMIT 10
),
top_posts AS (
  SELECT p.Id, p.Score, COUNT(v.Id) as vote_count
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  WHERE v.VoteTypeId = 2
  GROUP BY p.Id, p.Score
  ORDER BY vote_count DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) as post_count
  FROM Tags t
  JOIN Posts p ON t.Id = (SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(p.Tags, '><')))
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
)
SELECT 
  tu.DisplayName as top_user,
  tp.Score as top_post_score,
  tt.TagName as top_tag,
  ph.Comment as post_history_comment,
  v.VoteTypeId as vote_type,
  p.Title as post_title,
  COUNT(DISTINCT u.Id) as user_count
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostHistory ph ON p.Id = ph.PostId
JOIN Votes v ON p.Id = v.PostId
JOIN top_users tu ON u.Id = tu.Id
JOIN top_posts tp ON p.Id = tp.Id
JOIN top_tags tt ON p.Tags LIKE CONCAT('%>', tt.TagName, '<%')
WHERE v.VoteTypeId = 2
GROUP BY tu.DisplayName, tp.Score, tt.TagName, ph.Comment, v.VoteTypeId, p.Title
ORDER BY user_count DESC;
