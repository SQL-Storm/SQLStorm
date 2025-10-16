-- {"query": "31.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 146} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
        RANK() OVER(ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
    WHERE Reputation > 100000
),
user_badges AS (
    SELECT UserId, COUNT(*) AS badge_count
    FROM Badges
    GROUP BY UserId
),
top_users AS (
    SELECT ru.Id, ru.DisplayName, ru.Reputation, ub.badge_count
    FROM ranked_users ru
    JOIN user_badges ub ON ru.Id = ub.UserId
    WHERE ru.reputation_rank <= 100
)

SELECT tu.Id, tu.DisplayName, tu.Reputation, tu.badge_count
FROM top_users tu
ORDER BY tu.Reputation DESC;