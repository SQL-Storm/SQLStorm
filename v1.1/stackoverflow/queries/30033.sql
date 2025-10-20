-- {"query": "30033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 43} 
SELECT COUNT(*) AS TotalPosts, SUM(ViewCount) AS TotalViews
FROM Posts
WHERE CreationDate BETWEEN '2022-01-01' AND '2022-12-31';