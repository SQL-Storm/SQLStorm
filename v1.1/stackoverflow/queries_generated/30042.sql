-- {"query": "30042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 40} 
SELECT Users.Id, Users.Reputation, Posts.Id, Posts.Score, Comments.Id
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
JOIN Comments ON Posts.Id = Comments.PostId;