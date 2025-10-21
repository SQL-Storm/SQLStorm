-- {"query": "30040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 54} 

SELECT Users.DisplayName, Badges.Name, COUNT(*) AS BadgeCount
FROM Users
JOIN Badges ON Users.Id = Badges.UserId
GROUP BY Users.Id, Users.DisplayName, Badges.Name
ORDER BY BadgeCount DESC
LIMIT 10;
