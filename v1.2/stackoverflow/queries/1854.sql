WITH RecursiveTypeSums AS (
    SELECT
        pt.Id AS PostTypeId,
        pt.Name AS PostTypeName,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(p.Id) AS TotalPosts
    FROM PostTypes pt
    LEFT JOIN Posts p ON p.PostTypeId = pt.Id
    GROUP BY pt.Id, pt.Name
),
UserPostParticipation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS NumberOfPosts, 
        SUM(COALESCE(p.Score, 0)) AS SumPostScore,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.CreationDate) DESC) AS rn_latest_post,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u 
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopBadgedUsersIndex AS (
    SELECT 
        b.UserId,
        u.DisplayName,
        COUNT(*) AS BadgeCount,
        MAX(b.Date) AS LastBraceTiming,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    LEFT JOIN Users u ON u.Id = b.UserId
    GROUP BY b.UserId, u.DisplayName
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.NumberOfPosts,
    u.SumPostScore,
    u.AcceptedCount,
    u.LastPostDate,
    r.PostTypeId,
    r.PostTypeName,
    r.TotalScore,
    r.TotalPosts,
    t.BadgeCount,
    t.LastBraceTiming,
    t.GoldBadges,
    t.SilverBadges,
    t.BronzeBadges
FROM UserPostParticipation u
CROSS JOIN RecursiveTypeSums r
LEFT JOIN TopBadgedUsersIndex t ON t.UserId = u.UserId;