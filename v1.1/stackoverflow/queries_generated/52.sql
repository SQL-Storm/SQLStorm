-- {"query": "52.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 127} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_10_users AS (
    SELECT Id, Reputation
    FROM ranked_users
    WHERE rank <= 10
)

SELECT u.Id, u.DisplayName, u.Location, COUNT(DISTINCT p.Id) AS TotalPosts
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN top_10_users t ON u.Id = t.Id
WHERE u.Location IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Location
ORDER BY TotalPosts DESC;