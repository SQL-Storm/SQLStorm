-- {"query": "30006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 78} 
SELECT p.Id AS PostId, p.Title, COUNT(c.Id) AS CommentCount, SUM(v.VoteTypeId) AS TotalVotes
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY p.Id, p.Title
ORDER BY TotalVotes DESC
LIMIT 10;