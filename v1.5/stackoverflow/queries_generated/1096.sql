-- {"query": "1096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 462} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(b.Class = 1), 0) AS GoldBadges,
        COALESCE(SUM(b.Class = 2), 0) AS SilverBadges,
        COALESCE(SUM(b.Class = 3), 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id
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
        ELSE CONCAT('Views: ', p.ViewCount)
    END AS ViewInfo
FROM RankedPosts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostComments pc ON p.PostId = pc.PostId
WHERE p.RN = 1
ORDER BY us.PostCount DESC, p.Score DESC
LIMIT 50;
