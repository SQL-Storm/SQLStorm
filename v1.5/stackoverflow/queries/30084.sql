-- {"query": "30084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 35} 
SELECT COUNT(*) 
FROM Posts
WHERE PostTypeId = 1
AND CreationDate BETWEEN '2021-01-01' AND '2021-12-31';