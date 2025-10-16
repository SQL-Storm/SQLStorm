-- {"query": "50.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 93} 
SELECT p.Id, p.Title, p.Body, u.DisplayName, COUNT(c.Id) AS NumComments
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
AND p.Score > 0
GROUP BY p.Id, p.Title, p.Body, u.DisplayName
HAVING COUNT(c.Id) > 5
ORDER BY NumComments DESC;