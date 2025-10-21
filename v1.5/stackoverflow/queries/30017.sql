-- {"query": "30017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 63} 
SELECT p.Id, p.Title, p.Score, COUNT(c.Id) AS NumComments
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title, p.Score
ORDER BY NumComments DESC, p.Score DESC;