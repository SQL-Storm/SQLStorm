-- {"query": "30083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 68} 
SELECT SUM(p.Score) as TotalScore, COUNT(c.Id) as TotalComments
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.OwnerUserId
HAVING SUM(p.Score) > 100
ORDER BY TotalScore DESC;