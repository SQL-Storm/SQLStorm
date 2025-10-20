-- {"query": "30099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 48} 
SELECT DISTINCT u.Id, u.Reputation, COUNT(p.Id) as TotalPosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
GROUP BY u.Id, u.Reputation
ORDER BY TotalPosts DESC;