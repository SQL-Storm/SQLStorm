-- {"query": "30021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 23} 
SELECT AVG(Posts.Score) AS Average_Score, COUNT(Posts.Id) AS Post_Count
FROM Posts;