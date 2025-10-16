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
    SELECT p.Id AS post_id, p.Title, p.Score, p.OwnerUserId, u.DisplayName AS owner_name
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score >= 100
),
user_activity AS (
    SELECT u.Id AS user_id, u.DisplayName, COUNT(c.Id) AS comment_count, COUNT(v.Id) AS vote_count
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
)
SELECT tu.Id AS user_id,
       tu.DisplayName,
       ru.Reputation,
       hp.post_id,
       hp.Title,
       hp.Score,
       hp.owner_name,
       ua.comment_count,
       ua.vote_count
FROM top_users tu
JOIN ranked_users ru ON tu.Id = ru.Id
LEFT JOIN highly_voted_posts hp ON tu.Id = hp.OwnerUserId
LEFT JOIN user_activity ua ON tu.Id = ua.user_id
ORDER BY ru.Reputation DESC;