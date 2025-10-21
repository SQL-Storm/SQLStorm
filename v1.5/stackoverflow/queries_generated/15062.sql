-- {"query": "15062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 665}
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS ExclusiveGoldBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostActivityStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    pas.PostCount,
    pas.AveragePostScore,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = ubc.UserId AND v.VoteTypeId = 2), 0
    ) AS UpvoteCount,
    CASE 
        WHEN ubc.ExclusiveGoldBadges > 3 THEN 'Elite User'
        WHEN ubc.GoldBadgeCount > 10 THEN 'Power User'
        ELSE 'Regular User'
    END AS UserCategory,
    ROUND(
        (pas.AveragePostScore * 1.5) + 
        (ubc.GoldBadgeCount * 0.75) - 
        (COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.UserId = ubc.UserId AND v.VoteTypeId = 3), 0
        ) * 0.25), 2
    ) AS UserPerformanceIndex
FROM UserBadgeCounts ubc
JOIN PostActivityStats pas ON ubc.UserId = pas.OwnerUserId
WHERE ubc.BadgeRank <= 500
    AND pas.PostCount > 5
    AND (pas.MaxViewCount > 1000 OR ubc.GoldBadgeCount > 5)
ORDER BY UserPerformanceIndex DESC
LIMIT 100;
