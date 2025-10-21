-- {"query": "30066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 60} 
SELECT Posts.Id, Posts.Title, COUNT(Comments.Id) AS NumComments
FROM Posts
LEFT JOIN Comments ON Posts.Id = Comments.PostId
WHERE Posts.PostTypeId = 1
GROUP BY Posts.Id, Posts.Title
ORDER BY NumComments DESC
LIMIT 10;