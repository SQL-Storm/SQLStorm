-- {"query": "94.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 176} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, RANK() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rank <= 100
),
user_badges AS (
    SELECT UserId, COUNT(*) AS badge_count
    FROM Badges
    GROUP BY UserId
),
user_vote_count AS (
    SELECT UserId, COUNT(*) AS total_votes
    FROM Votes
    GROUP BY UserId
)
SELECT tu.Id AS user_id, tu.DisplayName AS user_name, tu.Reputation AS user_reputation, ub.badge_count, uvc.total_votes
FROM top_users tu
JOIN user_badges ub ON tu.Id = ub.UserId
JOIN user_vote_count uvc ON tu.Id = uvc.UserId
ORDER BY tu.Reputation DESC;