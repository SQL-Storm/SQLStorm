-- {"query": "30079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 75} 
SELECT p.Id, p.Title, COUNT(c.Id) AS Num_Comments, SUM(v.VoteTypeId) AS Total_Votes
FROM Posts p
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY p.Id, p.Title
ORDER BY Num_Comments DESC, Total_Votes DESC;