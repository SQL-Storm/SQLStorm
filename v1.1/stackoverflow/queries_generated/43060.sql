-- {"query": "43060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 506} 

WITH UserBadgesCount AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
HighScoredQuestionsWithUsers AS (
    SELECT 
        tq.Id,
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    FROM TopQuestions tq
    JOIN Users u ON tq.OwnerUserId = u.Id
    JOIN UserBadgesCount ub ON u.Id = ub.Id
    WHERE tq.rn <= 5
)
SELECT 
    hsq.OwnerDisplayName,
    hsq.GoldBadges,
    hsq.SilverBadges,
    hsq.BronzeBadges,
    AVG(hsq.Score) AS AvgQuestionScore,
    SUM(hsq.ViewCount) AS TotalViewCount,
    AVG(hsq.AnswerCount) AS AvgAnswerCount
FROM HighScoredQuestionsWithUsers hsq
GROUP BY hsq.OwnerDisplayName, hsq.GoldBadges, hsq.SilverBadges, hsq.BronzeBadges
ORDER BY AvgQuestionScore DESC, TotalViewCount DESC
LIMIT 10;
