-- {"query": "15041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 576}
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS ExclusiveBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostInteractions AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    pi.VoteCount,
    pi.AvgPostScore,
    pi.MaxViewCount,
    CASE 
        WHEN pi.AvgPostScore > 10 AND ubc.GoldBadgeCount > 5 THEN 'Elite User'
        WHEN pi.AvgPostScore > 5 THEN 'Experienced User'
        ELSE 'Regular User'
    END AS UserTier,
    COALESCE(pi.MedianScore, 0) * (1 + LEAST(ubc.ExclusiveBadges * 0.1, 0.5)) AS AdjustedScore
FROM UserBadgeCounts ubc
FULL OUTER JOIN PostInteractions pi ON ubc.UserId = pi.OwnerUserId
WHERE 
    (ubc.BadgeRank <= 100 OR pi.VoteCount > 50)
    AND (ubc.GoldBadgeCount > 0 OR pi.MaxViewCount > 1000)
ORDER BY AdjustedScore DESC
LIMIT 250;
