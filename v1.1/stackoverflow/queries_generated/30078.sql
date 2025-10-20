-- {"query": "30078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 44} 
SELECT u.DisplayName, u.Reputation, COUNT(*) AS TotalPosts
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
GROUP BY u.DisplayName, u.Reputation
ORDER BY TotalPosts DESC;