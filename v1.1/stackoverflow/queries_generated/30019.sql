-- {"query": "30019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 69} 
SELECT DISTINCT Users.Id, Users.DisplayName, Posts.Id AS PostId, Posts.Title, Comments.Id AS CommentId
FROM Users
INNER JOIN Posts ON Users.Id = Posts.OwnerUserId
LEFT JOIN Comments ON Posts.Id = Comments.PostId
WHERE Users.Reputation > 10000
ORDER BY Users.Id, PostId DESC, CommentId;