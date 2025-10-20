-- {"query": "30022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 67} 

SELECT p.Id as PostId, p.Title, COUNT(c.Id) as NumComments
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title
ORDER BY NumComments DESC, p.Id
LIMIT 10;
