-- {"query": "44.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 84} 
SELECT p.Id, p.Title, p.ViewCount, v.VoteTypeId, COUNT(c.Id) AS CommentCount
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title, p.ViewCount, v.VoteTypeId
ORDER BY p.ViewCount DESC;