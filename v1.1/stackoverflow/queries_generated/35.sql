-- {"query": "35.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 56} 
SELECT p.Id AS PostId, p.Title, COUNT(c.Id) AS CommentCount
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title
ORDER BY CommentCount DESC;