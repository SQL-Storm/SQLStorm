-- {"query": "59.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 100} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, 
           ROW_NUMBER() OVER(ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
top_users AS (
    SELECT *
    FROM ranked_users
    WHERE user_rank <= 100
)
SELECT u.DisplayName, u.Reputation, b.Name AS BadgeName
FROM top_users u
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE b.Class = 1
ORDER BY u.Reputation DESC;