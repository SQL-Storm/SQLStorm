-- {"query": "30039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 53} 
SELECT p.Id, p.Title, COUNT(v.Id) AS VoteCount
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title
ORDER BY VoteCount DESC;