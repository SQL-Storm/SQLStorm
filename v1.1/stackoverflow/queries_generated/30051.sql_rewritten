-- {"query": "30051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 57} 
SELECT 
    u.DisplayName,
    SUM(p.Score) AS TotalScore
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
GROUP BY u.DisplayName
ORDER BY TotalScore DESC
LIMIT 10;