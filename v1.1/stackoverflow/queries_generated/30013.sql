-- {"query": "30013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 53} 
SELECT u.DisplayName, b.Name, p.CreationDate
FROM Users u
JOIN Badges b ON u.Id = b.UserId
JOIN Posts p ON p.OwnerUserId = u.Id
WHERE b.Class = 1
ORDER BY p.CreationDate DESC;