WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation
    FROM users u
)
SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation
FROM UserMetrics um
GROUP BY
    um.UserId,
    um.DisplayName,
    um.Reputation;