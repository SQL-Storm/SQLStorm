-- {"query": "15069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 163450, "output_tokens": 47860} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank,
        AVG(u.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AvgYearlyReputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
),
PostAnalytics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Tags,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS Answers,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.BadgeRank,
    pa.Id AS TopQuestionId,
    pa.Score AS TopQuestionScore,
    CASE 
        WHEN pa.ViewCount > 10000 THEN 'Viral'
        WHEN pa.ViewCount > 5000 THEN 'Popular'
        ELSE 'Normal'
    END AS QuestionPopularity,
    ROUND(ubc.AvgYearlyReputation * LEAST(pa.Score * 0.5, 1.5), 2) AS AdjustedReputationScore,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubc.UserId AND c.Score > 5
    ) AS HighScoringComments
FROM UserBadgeCounts ubc
JOIN PostAnalytics pa ON 1=1
WHERE ubc.GoldBadgeCount > 2
    AND pa.ScoreRank <= 100
    AND pa.Answers > 3
    AND pa.Tags LIKE '%<sql>%'
ORDER BY AdjustedReputationScore DESC
LIMIT 50;