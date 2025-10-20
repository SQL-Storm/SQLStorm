WITH RecursiveBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        b.Name AS BadgeName,
        COUNT(*) OVER (PARTITION BY u.Id, b.Class) AS BadgeClassCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS RecentRank,
        TRIM(BOTH ' ' FROM CAST(ROUND(u.Reputation * (CASE WHEN b.Class = 1 THEN 1.5 WHEN b.Class = 2 THEN 1.2 ELSE 1 END), 0) AS TEXT)) AS ReputationWeight
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
)
SELECT
    UserId,
    DisplayName,
    Class,
    BadgeName,
    BadgeClassCount,
    RecentRank,
    ReputationWeight
FROM RecursiveBadges
WHERE RecentRank = 1
GROUP BY
    UserId,
    DisplayName,
    Class,
    BadgeName,
    BadgeClassCount,
    RecentRank,
    ReputationWeight;