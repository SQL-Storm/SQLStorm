-- {"query": "30061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 61} 
SELECT Posts.Id, Posts.Title, Users.DisplayName, COUNT(Comments.Id) AS CommentCount
FROM Posts
LEFT JOIN Comments ON Posts.Id = Comments.PostId
LEFT JOIN Users ON Posts.OwnerUserId = Users.Id
GROUP BY Posts.Id, Posts.Title, Users.DisplayName
ORDER BY CommentCount DESC;