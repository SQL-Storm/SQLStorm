-- {"query": "30024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 66} 
SELECT DISTINCT u.DisplayName, p.Title, COUNT(v.Id) AS TotalVotes
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE u.Reputation > 10000
GROUP BY u.DisplayName, p.Title
ORDER BY TotalVotes DESC;