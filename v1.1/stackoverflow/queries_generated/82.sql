-- {"query": "82.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 190} 
WITH UserReputationPerDay AS (
    SELECT UserId, SUM(Reputation) AS TotalReputation, COUNT(DISTINCT DATE(CreationDate)) AS ActiveDays
    FROM Users
    GROUP BY UserId
),
UserBadgeCount AS (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
),
UserPostCount AS (
    SELECT UserId, COUNT(*) AS PostCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT u.DisplayName, u.LastAccessDate, r.TotalReputation, r.ActiveDays, b.BadgeCount, p.PostCount
FROM Users u
LEFT JOIN UserReputationPerDay r ON u.Id = r.UserId
LEFT JOIN UserBadgeCount b ON u.Id = b.UserId
LEFT JOIN UserPostCount p ON u.Id = p.UserId
ORDER BY r.TotalReputation DESC, p.PostCount DESC;