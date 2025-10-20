-- {"query": "30001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 73} 
SELECT p.Id, p.CreationDate, p.Score, COUNT(v.Id) as VoteCount
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.CreationDate, p.Score
ORDER BY VoteCount DESC, p.Score DESC, p.CreationDate ASC;