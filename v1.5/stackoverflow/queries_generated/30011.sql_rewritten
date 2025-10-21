-- {"query": "30011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 58} 
SELECT u.Id as UserId, u.DisplayName, COUNT(DISTINCT p.Id) as TotalPosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
GROUP BY u.Id, u.DisplayName
ORDER BY TotalPosts DESC
LIMIT 10;