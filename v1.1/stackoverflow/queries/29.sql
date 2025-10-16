-- {"query": "29.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 163} 
WITH recursive cte AS (
    SELECT Id, PostTypeId, CreationDate, OwnerUserId, ViewCount, Score, Title, AnswerCount, Tags
    FROM Posts
    WHERE PostTypeId = 1 -- Questions
    UNION ALL
    SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.ViewCount, p.Score, p.Title, p.AnswerCount, p.Tags
    FROM Posts p
    INNER JOIN cte ON p.ParentId = cte.Id
)
SELECT c.Id, c.CreationDate, u.DisplayName AS OwnerName, c.ViewCount, c.Score, c.Title, c.AnswerCount, c.Tags
FROM cte c
LEFT JOIN Users u ON c.OwnerUserId = u.Id
ORDER BY c.CreationDate DESC;