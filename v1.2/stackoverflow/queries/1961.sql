WITH RECURSIVE TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        CASE WHEN EXISTS (
            SELECT 1
            FROM Votes v
            JOIN Posts p ON v.PostId = p.Id
            WHERE v.UserId = u.Id
              AND v.VoteTypeId = 2
              AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
        ) THEN 1 ELSE 0 END AS RecentUpvoteActivity
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RepStats AS (
    SELECT
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY Reputation) AS Rep90
    FROM Users
)
SELECT
    t.Id,
    t.DisplayName,
    t.Reputation,
    t.GoldBadges,
    t.SilverBadges,
    t.BronzeBadges,
    t.RecentUpvoteActivity
FROM TopUsers t
CROSS JOIN RepStats r
WHERE t.Reputation >= r.Rep90
ORDER BY t.Reputation DESC;