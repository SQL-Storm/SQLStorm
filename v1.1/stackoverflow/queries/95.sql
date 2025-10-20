-- {"query": "95.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 219} 
WITH ranked_users AS (
    SELECT 
        Id, 
        DisplayName, 
        Reputation, 
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
top_badges AS (
    SELECT 
        b.Id,
        b.UserId,
        b.Name,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS badge_rank
    FROM Badges b
),
user_ranked_badges AS (
    SELECT
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        tb.Name AS BadgeName,
        tb.Date,
        tb.badge_rank
    FROM ranked_users tu
    LEFT JOIN top_badges tb ON tu.Id = tb.UserId AND tb.badge_rank <= 3
)
SELECT 
    urb.DisplayName AS UserDisplayName,
    urb.Reputation,
    urb.BadgeName,
    urb.Date AS BadgeDate
FROM user_ranked_badges urb
WHERE urb.badge_rank IS NOT NULL
ORDER BY urb.Reputation DESC, urb.badge_rank;