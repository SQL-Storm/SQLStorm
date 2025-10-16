WITH UserReputationPerDay AS (
    SELECT Id AS UserId,
           SUM(Reputation) AS TotalReputation,
           COUNT(DISTINCT CAST(CreationDate AS DATE)) AS ActiveDays
    FROM Users
    GROUP BY Id
),
UserBadgeCount AS (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
),
UserPostCount AS (
    SELECT OwnerUserId AS UserId, COUNT(*) AS PostCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT u.DisplayName,
       u.LastAccessDate,
       r.TotalReputation,
       r.ActiveDays,
       b.BadgeCount,
       p.PostCount
FROM Users u
LEFT JOIN UserReputationPerDay r ON u.Id = r.UserId
LEFT JOIN UserBadgeCount b ON u.Id = b.UserId
LEFT JOIN UserPostCount p ON u.Id = p.UserId
ORDER BY r.TotalReputation DESC, p.PostCount DESC;