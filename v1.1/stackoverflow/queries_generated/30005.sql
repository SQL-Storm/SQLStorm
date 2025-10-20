-- {"query": "30005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 46} 
SELECT Users.Id, Users.DisplayName, SUM(Posts.ViewCount) AS TotalViewCount
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
GROUP BY Users.Id, Users.DisplayName
ORDER BY TotalViewCount DESC;