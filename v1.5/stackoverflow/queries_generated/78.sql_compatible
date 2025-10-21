WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rank <= 100
)
SELECT u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS num_posts, SUM(v.VoteTypeId) AS total_votes
FROM top_users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY u.DisplayName, u.Reputation
ORDER BY num_posts DESC, total_votes DESC;