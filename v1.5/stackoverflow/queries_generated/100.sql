-- {"query": "100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 124} 
WITH cte_rn AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn
    FROM Posts p
)
SELECT r1.Id, r1.Title, r1.Score, r1.ViewCount, r1.AnswerCount
FROM cte_rn r1
JOIN cte_rn r2 ON r1.rn = r2.rn
WHERE r1.PostTypeId = 1
   AND r2.PostTypeId = 2;