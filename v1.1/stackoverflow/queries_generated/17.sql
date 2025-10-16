-- {"query": "17.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 81} 
SELECT p.Id AS PostId, COUNT(DISTINCT c.UserId) AS DistinctCommentUsers
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
AND p.Score > 5
AND p.AcceptedAnswerId IS NOT NULL
AND p.ClosedDate IS NULL
GROUP BY p.Id
ORDER BY DistinctCommentUsers DESC;