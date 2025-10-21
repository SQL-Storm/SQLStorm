-- {"query": "30016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 52} 
SELECT Users.Id, Users.DisplayName, Users.Reputation, COUNT(Posts.Id) AS NumPosts
FROM Users
LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
GROUP BY Users.Id, Users.DisplayName, Users.Reputation
ORDER BY NumPosts DESC;