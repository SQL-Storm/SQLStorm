-- {"query": "15094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 660}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(u.Reputation) OVER (PARTITION BY b.Class) AS AvgReputationByBadgeClass,
        RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostActivityMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        FIRST_VALUE(p.Title) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS TopRatedPostTitle
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    pam.PostCount,
    pam.AvgPostScore,
    ubs.AvgReputationByBadgeClass,
    ubs.BadgeRank,
    pam.TopRatedPostTitle,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ubs.UserId),
        0
    ) AS CommentCount,
    CASE 
        WHEN ubs.TotalBadges > 50 AND pam.AvgPostScore > 10 THEN 'Elite User'
        WHEN ubs.TotalBadges > 20 THEN 'Power User'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserBadgeStats ubs
JOIN PostActivityMetrics pam ON ubs.UserId = pam.OwnerUserId
WHERE 
    ubs.TotalBadges > 0 
    AND pam.PostCount > 5
    AND (
        pam.LatestPostDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
        OR ubs.GoldBadges > 3
    )
ORDER BY 
    ubs.TotalBadges DESC,
    pam.AvgPostScore DESC
LIMIT 100;
