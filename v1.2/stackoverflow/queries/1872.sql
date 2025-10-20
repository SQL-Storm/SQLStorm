WITH RECURSIVE RankedUserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS DisplayName,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS rn
    FROM Users u
    JOIN Badges b ON b.UserId = u.Id
)
SELECT
    UserId,
    DisplayName,
    BadgeName,
    BadgeDate
FROM RankedUserBadges
WHERE rn = 1
ORDER BY UserId;