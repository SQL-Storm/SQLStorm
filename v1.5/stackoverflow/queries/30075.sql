-- {"query": "30075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 44} 
SELECT Posts.Id, Posts.Title, COUNT(*) as TotalComments
FROM Posts
JOIN Comments ON Posts.Id = Comments.PostId
GROUP BY Posts.Id, Posts.Title
ORDER BY TotalComments DESC;