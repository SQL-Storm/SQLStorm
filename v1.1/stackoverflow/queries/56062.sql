-- {"query": "56062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 389} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) as post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 0
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) as post_count
  FROM Tags t
  JOIN Posts p ON t.Id = (SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(p.Tags, '><')))
  WHERE p.PostTypeId = 1 AND p.Score > 0
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
),
user_scores AS (
  SELECT u.Id, u.DisplayName, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) as score
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  WHERE v.VoteTypeId IN (2, 3)
  GROUP BY u.Id, u.DisplayName
)
SELECT 
  tu.DisplayName as top_user, 
  tt.TagName as top_tag, 
  us.score as user_score, 
  p.Title, 
  p.Score as post_score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.CommentCount
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN top_tags tt ON p.Id = (SELECT Id FROM Posts WHERE Tags LIKE '%<' || tt.TagName || '>%')
JOIN user_scores us ON tu.Id = us.Id
WHERE p.PostTypeId = 1 AND p.Score > 0
ORDER BY p.Score DESC, p.ViewCount DESC, us.score DESC;