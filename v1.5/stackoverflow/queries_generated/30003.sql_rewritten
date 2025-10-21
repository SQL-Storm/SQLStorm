-- {"query": "30003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 46} 
SELECT Users.DisplayName, COUNT(Posts.Id) AS PostCount
FROM Users
LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
GROUP BY Users.DisplayName
ORDER BY PostCount DESC
LIMIT 10;