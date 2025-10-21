-- {"query": "30057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 41} 
SELECT Users.DisplayName, SUM(Posts.Score) as TotalScore
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
GROUP BY Users.DisplayName
ORDER BY TotalScore DESC;