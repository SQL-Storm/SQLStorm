-- {"query": "30037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 60} 
SELECT u.DisplayName, COUNT(DISTINCT p.Id) AS PostCount
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN Votes v ON p.Id = v.PostId
GROUP BY u.DisplayName
ORDER BY PostCount DESC
LIMIT 10;