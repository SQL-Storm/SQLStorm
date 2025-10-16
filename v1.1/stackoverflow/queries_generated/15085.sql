-- {"query": "15085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 200810, "output_tokens": 58836} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS ExactGoldCount,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
), 
TopQuestionStats AS (
    SELECT 
        p.OwnerUserId,
        MAX(p.Score) AS MaxQuestionScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT CASE WHEN p.AnswerCount > 3 THEN p.Id END) AS ComplexQuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.BadgeRank,
    tqs.MaxQuestionScore,
    tqs.AvgViewCount,
    tqs.ComplexQuestionCount,
    COALESCE(tqs.MaxQuestionScore, 0) + COALESCE(ubc.GoldBadgeCount * 2, 0) AS CompositeScore,
    CASE 
        WHEN ubc.GoldBadgeCount > 10 AND tqs.MaxQuestionScore > 50 THEN 'Elite User'
        WHEN ubc.GoldBadgeCount > 5 THEN 'Power User'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserBadgeCounts ubc
LEFT JOIN TopQuestionStats tqs ON ubc.UserId = tqs.OwnerUserId
WHERE ubc.GoldBadgeCount > 0
    AND (tqs.AvgViewCount > 100 OR ubc.GoldBadgeCount > 5)
ORDER BY CompositeScore DESC
LIMIT 100;