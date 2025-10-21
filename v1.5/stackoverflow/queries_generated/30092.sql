-- {"query": "30092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 49} 

SELECT Users.DisplayName, SUM(Posts.Score) AS TotalScore
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId = 2
GROUP BY Users.DisplayName
ORDER BY TotalScore DESC;
