-- {"query": "56015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 282} 

WITH top_users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) as post_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY u.Id, u.DisplayName
  ORDER BY post_count DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, COUNT(p.Id) as post_count
  FROM Tags t
  JOIN Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
  WHERE p.PostTypeId = 1 AND p.Score > 10
  GROUP BY t.TagName
  ORDER BY post_count DESC
  LIMIT 10
)
SELECT 
  tu.DisplayName, 
  tu.post_count, 
  tt.TagName, 
  COUNT(v.Id) as vote_count
FROM top_users tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN Votes v ON p.Id = v.PostId
JOIN top_tags tt ON p.Id = ANY((SELECT array_agg(Id) FROM Posts WHERE Tags LIKE '%<' || tt.TagName || '>%'))
WHERE v.VoteTypeId = 2 AND p.PostTypeId = 1 AND p.Score > 10
GROUP BY tu.DisplayName, tu.post_count, tt.TagName
ORDER BY vote_count DESC;
