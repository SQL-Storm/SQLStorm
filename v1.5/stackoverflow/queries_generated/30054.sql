-- {"query": "30054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 70} 

SELECT u.DisplayName AS UserDisplayName, p.Title AS PostTitle, COUNT(c.Id) AS CommentCount
FROM Users u
JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY u.DisplayName, p.Title
ORDER BY CommentCount DESC
LIMIT 10;
