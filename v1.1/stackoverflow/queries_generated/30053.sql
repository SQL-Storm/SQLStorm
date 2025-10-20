-- {"query": "30053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 57} 
SELECT Users.Id, Users.Reputation, COUNT(DISTINCT Posts.Id) AS TotalPosts
FROM Users
LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
WHERE Users.Reputation > 1000
GROUP BY Users.Id, Users.Reputation
ORDER BY TotalPosts DESC;