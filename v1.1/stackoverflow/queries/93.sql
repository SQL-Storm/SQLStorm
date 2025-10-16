WITH ranked_users AS (
    SELECT 
        Id,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_10_users AS (
    SELECT 
        Id,
        Reputation,
        rank
    FROM ranked_users
    WHERE rank <= 10
)
SELECT 
    c.UserId,
    u.DisplayName,
    u.Location,
    c.Score,
    c.Text
FROM Comments c
JOIN top_10_users t ON c.UserId = t.Id
JOIN Users u ON u.Id = t.Id
WHERE c.Score > 5
GROUP BY
    c.UserId,
    u.DisplayName,
    u.Location,
    c.Score,
    c.Text,
    u.Reputation
ORDER BY u.Reputation DESC;