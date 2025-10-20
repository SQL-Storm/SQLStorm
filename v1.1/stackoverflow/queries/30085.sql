-- {"query": "30085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 65} 
SELECT SUM(p.ViewCount) AS TotalViewCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
INNER JOIN Votes v ON p.Id = v.PostId
WHERE u.Reputation > 10000
AND p.PostTypeId = 1
AND v.VoteTypeId = 2;