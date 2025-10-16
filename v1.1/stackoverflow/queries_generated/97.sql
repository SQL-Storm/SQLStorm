-- {"query": "97.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 114} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_10_users AS (
    SELECT *
    FROM ranked_users
    WHERE rank <= 10
)
SELECT u.Id, u.DisplayName, u.Reputation, COUNT(*) AS TotalPosts
FROM top_10_users u
JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 2
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalPosts DESC;