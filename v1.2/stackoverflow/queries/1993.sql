WITH RecentActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ARRAY_AGG(DISTINCT b.Name) FILTER (WHERE b.Date IS NOT NULL) AS badge_list,
        COUNT(b.Id) AS TotalBadges
    FROM users u
    LEFT JOIN badges b
        ON b.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation
)
SELECT *
FROM RecentActiveUsers;