-- {"query": "30018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 45} 
SELECT Users.DisplayName, COUNT(*) AS TotalPosts
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId IN (1, 2)
GROUP BY Users.DisplayName
ORDER BY TotalPosts DESC;