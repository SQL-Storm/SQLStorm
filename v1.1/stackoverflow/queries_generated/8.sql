-- {"query": "8.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 76} 
SELECT p.Id AS PostId, p.Title, u.DisplayName, COUNT(c.Id) AS TotalComments
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title, u.DisplayName
ORDER BY TotalComments DESC, p.Id;