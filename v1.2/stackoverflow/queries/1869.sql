WITH LatestUserBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Date < DATE '2024-01-01'
), UserActivities AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT ph.Id) AS EditActivities,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN PostHistory ph
        ON ph.UserId = u.Id
        AND ph.PostHistoryTypeId IN (4,5,6,10,11)
    GROUP BY u.Id
)
SELECT
    lub.UserId,
    lub.Name,
    lub.Class,
    lub.rn,
    ua.EditActivities,
    ua.LastEditDate
FROM LatestUserBadges lub
LEFT JOIN UserActivities ua
    ON ua.UserId = lub.UserId
WHERE lub.rn = 1;