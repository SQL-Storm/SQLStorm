-- {"query": "30058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 59} 

SELECT Users.Id, Users.Reputation, COUNT(*) as TotalPosts
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
WHERE Users.Reputation > 10000
GROUP BY Users.Id, Users.Reputation
ORDER BY TotalPosts DESC
LIMIT 10;
