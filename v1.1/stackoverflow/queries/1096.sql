WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    p.PostId,
    p.Title,
    u.DisplayName AS OwnerName,
    COALESCE(pc.CommentCount, 0) AS Comments,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.PostCount,
    CASE 
        WHEN p.Score >= 10 THEN 'Popular'
        WHEN p.Score >= 5 THEN 'Moderately Popular'
        ELSE 'Less Popular' 
    END AS PopularityLevel,
    CASE 
        WHEN p.ViewCount IS NULL THEN 'No Views'
        ELSE 'Views: ' || CAST(p.ViewCount AS VARCHAR)
    END AS ViewInfo
FROM RankedPosts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostComments pc ON p.PostId = pc.PostId
WHERE p.RN = 1
ORDER BY us.PostCount DESC, p.Score DESC
LIMIT 50;