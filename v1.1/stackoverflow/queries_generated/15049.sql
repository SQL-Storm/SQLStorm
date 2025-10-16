-- {"query": "15049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116750, "output_tokens": 34375} 
WITH UserBadgeRankings AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY COUNT(b.Id) DESC) AS ClassRankPerBadgeClass
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostActivityMetrics AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) AS HighScoringAnswers,
        MAX(p.LastActivityDate) AS MostRecentActivity,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT 
    ubr.Id AS UserId,
    ubr.DisplayName,
    ubr.TotalBadges,
    ubr.BadgeRank,
    pam.AvgPostScore,
    pam.TotalViewCount,
    pam.HighScoringAnswers,
    COALESCE(pam.MedianScore, 0) AS NormalizedMedianScore,
    CASE 
        WHEN pam.AvgPostScore > 10 AND ubr.TotalBadges > 5 THEN 'High Impact'
        WHEN pam.AvgPostScore > 5 AND ubr.TotalBadges > 2 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ContributionTier,
    DATEPART(year, pam.MostRecentActivity) AS MostRecentActivityYear
FROM UserBadgeRankings ubr
JOIN PostActivityMetrics pam ON ubr.Id = pam.OwnerUserId
WHERE 
    ubr.ClassRankPerBadgeClass <= 10
    AND (pam.HighScoringAnswers > 3 OR ubr.TotalBadges > 10)
    AND pam.AvgPostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)
ORDER BY 
    ubr.BadgeRank, 
    pam.AvgPostScore DESC
LIMIT 500;