-- {"query": "30052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 127} 
WITH recursive cte AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM cte WHERE n < 100
)
SELECT 
   p.Id,
   p.CreationDate,
   p.Title,
   u.DisplayName,
   COUNT(v.Id) AS VoteCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
JOIN cte ON cte.n = 1
GROUP BY p.Id, p.CreationDate, p.Title, u.DisplayName
ORDER BY VoteCount DESC;