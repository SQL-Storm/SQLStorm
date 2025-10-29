-- {"query": "15018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 685}
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        SUM(p.Score) AS TotalPostScore,
        AVG(NULLIF(p.ViewCount, 0)) AS AvgPostViews,
        COUNT(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS QuestionsWithAcceptedAnswer,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ps.TotalPostScore,
    ps.AvgPostViews,
    ps.QuestionsWithAcceptedAnswer,
    ps.MedianPostScore,
    CASE 
        WHEN ubc.TotalBadges > 10 AND ps.TotalPostScore > 100 THEN 'High Contributor'
        WHEN ubc.TotalBadges BETWEEN 5 AND 10 THEN 'Moderate Contributor'
        ELSE 'Low Contributor'
    END AS ContributorCategory,
    ROW_NUMBER() OVER (
        PARTITION BY 
            CASE 
                WHEN ubc.TotalBadges > 10 AND ps.TotalPostScore > 100 THEN 1 
                WHEN ubc.TotalBadges BETWEEN 5 AND 10 THEN 2 
                ELSE 3 
            END 
        ORDER BY ubc.TotalBadges + ps.TotalPostScore DESC
    ) AS CategoryRank
FROM UserBadgeCounts ubc
JOIN PostStats ps ON ubc.UserId = ps.OwnerUserId
WHERE ubc.TotalBadges > 0 
    AND ps.AvgPostViews > 50
    AND ps.QuestionsWithAcceptedAnswer > 0
ORDER BY ContributorCategory, CategoryRank
LIMIT 100;
