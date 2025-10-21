-- {"query": "41.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 96} 
SELECT u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS TotalPosts, MAX(v.CreationDate) AS LatestVoteDate
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE u.Reputation > 10000
GROUP BY u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 5
ORDER BY LatestVoteDate DESC;