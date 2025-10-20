-- {"query": "14.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 125} 
WITH user_reputation AS (
    SELECT UserId, SUM(Reputation) AS TotalReputation
    FROM Users
    GROUP BY UserId
),
top_users AS (
    SELECT Id, DisplayName, TotalReputation
    FROM Users
    JOIN user_reputation ON Users.Id = user_reputation.UserId
    ORDER BY TotalReputation DESC
    LIMIT 10
)
SELECT top_users.DisplayName, COUNT(Posts.Id) AS TotalPosts
FROM top_users
JOIN Posts ON top_users.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId = 1
GROUP BY top_users.DisplayName
ORDER BY TotalPosts DESC;