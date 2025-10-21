-- {"query": "30012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 67} 
SELECT Posts.Id, Users.DisplayName, Posts.Title, Comments.Text
FROM Posts
JOIN Users ON Posts.OwnerUserId = Users.Id
JOIN Comments ON Posts.Id = Comments.PostId
WHERE Posts.PostTypeId = 1
AND Posts.ClosedDate IS NULL
AND Users.Reputation > 1000
ORDER BY Posts.ViewCount DESC;