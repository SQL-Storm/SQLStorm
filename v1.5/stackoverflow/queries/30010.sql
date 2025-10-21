-- {"query": "30010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 41} 
SELECT Posts.Id, Posts.Title, Posts.Body, Users.DisplayName
FROM Posts
JOIN Users ON Posts.OwnerUserId = Users.Id
WHERE Posts.PostTypeId = 1
ORDER BY Posts.ViewCount DESC;