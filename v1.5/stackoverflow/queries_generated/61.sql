-- {"query": "61.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 101} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, Reputation, rank
    FROM ranked_users
    WHERE rank <= 100
)
SELECT u.Id, u.DisplayName, u.Reputation, b.Name AS BadgeName
FROM top_users u
JOIN Badges b ON u.Id = b.UserId
WHERE b.Class = 1
ORDER BY u.Reputation DESC;