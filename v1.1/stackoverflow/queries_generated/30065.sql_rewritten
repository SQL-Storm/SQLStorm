-- {"query": "30065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 51} 
SELECT u.DisplayName, COUNT(p.Id) AS PostCount
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
GROUP BY u.DisplayName
ORDER BY PostCount DESC;