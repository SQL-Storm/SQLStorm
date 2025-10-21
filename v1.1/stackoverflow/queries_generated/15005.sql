-- {"query": "15005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 809}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        AVG(CASE WHEN b.Class = 1 THEN 1.0 ELSE 0.0 END) AS GoldBadgeRatio,
        ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
PostActivityMetrics AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(*) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
        MAX(p.CreationDate) AS LatestPostDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId, p.PostTypeId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.BadgeCount,
    ubs.GoldBadgeRatio,
    COALESCE(qam.PostCount, 0) AS QuestionCount,
    COALESCE(qam.TotalScore, 0) AS QuestionTotalScore,
    COALESCE(aam.PostCount, 0) AS AnswerCount,
    COALESCE(aam.TotalScore, 0) AS AnswerTotalScore,
    (COALESCE(qam.TotalScore, 0) + COALESCE(aam.TotalScore, 0)) / 
        NULLIF((COALESCE(qam.PostCount, 0) + COALESCE(aam.PostCount, 0)), 0) AS AvgOverallScore,
    GREATEST(COALESCE(qam.LatestPostDate, '1970-01-01'), COALESCE(aam.LatestPostDate, '1970-01-01')) AS MostRecentActivity,
    CASE 
        WHEN ubs.BadgeRank <= 100 THEN 'Top Contributor'
        WHEN ubs.BadgeCount > 10 THEN 'Active User'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserBadgeStats ubs
LEFT JOIN PostActivityMetrics qam ON ubs.UserId = qam.OwnerUserId AND qam.PostTypeId = 1
LEFT JOIN PostActivityMetrics aam ON ubs.UserId = aam.OwnerUserId AND aam.PostTypeId = 2
WHERE ubs.BadgeCount > 0
    AND (COALESCE(qam.PostCount, 0) + COALESCE(aam.PostCount, 0)) > 5
    AND ubs.GoldBadgeRatio > 0.1
ORDER BY AvgOverallScore DESC
LIMIT 1000;
