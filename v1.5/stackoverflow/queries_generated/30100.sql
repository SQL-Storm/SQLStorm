-- {"query": "30100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 50} 
SELECT DISTINCT u.Id, u.Reputation, (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts
FROM Users u
LEFT JOIN Badges b ON u.Id = b.UserId
ORDER BY TotalPosts DESC;