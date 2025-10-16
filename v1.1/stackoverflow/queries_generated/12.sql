-- {"query": "12.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 257} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, RANK() OVER (ORDER BY Reputation DESC) AS reputation_rank
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE reputation_rank <= 100
),
highly_voted_posts AS (
    SELECT p.Id AS post_id, p.Title, p.Score, u.DisplayName AS owner_name
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score >= 100
),
user_activity AS (
    SELECT u.DisplayName, COUNT(c.Id) AS comment_count, COUNT(v.Id) AS vote_count
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.DisplayName
)
SELECT tu.Id AS user_id, tu.DisplayName, ru.Reputation, hp.post_id, hp.Title, hp.Score, hp.owner_name, ua.comment_count, ua.vote_count
FROM top_users tu
JOIN ranked_users ru ON tu.Id = ru.Id
JOIN highly_voted_posts hp ON ru.Id = hp.OwnerUserId
LEFT JOIN user_activity ua ON tu.DisplayName = ua.DisplayName
ORDER BY ru.Reputation DESC;