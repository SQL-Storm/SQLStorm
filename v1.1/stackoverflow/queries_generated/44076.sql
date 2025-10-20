-- {"query": "44076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 174344, "output_tokens": 59743} 

SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName, u.Reputation, COUNT(v.Id) AS VoteCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1 AND p.Score >= 10 AND v.VoteTypeId = 2
GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName, u.Reputation
ORDER BY VoteCount DESC
LIMIT 100;
