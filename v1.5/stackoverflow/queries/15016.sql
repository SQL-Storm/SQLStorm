-- {"query": "15016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 39695, "output_tokens": 11780} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostAnalytics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.Score) AS MaxPostScore,
        AVG(NULLIF(p.Score, 0)) AS AvgNonZeroScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    pa.TotalPosts,
    pa.QuestionCount,
    pa.AnswerCount,
    pa.MaxPostScore,
    pa.AvgNonZeroScore,
    pa.MaxViewCount,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubs.UserId) AS CommentCount,
    COALESCE(pa.MaxPostScore, 0) + COALESCE(ubs.TotalBadges, 0) * 0.5 AS CompositeStat,
    CASE 
        WHEN ubs.TotalBadges > 10 AND pa.TotalPosts > 5 THEN 'Active Contributor'
        WHEN ubs.TotalBadges > 5 AND pa.TotalPosts > 0 THEN 'Emerging Contributor'
        ELSE 'New User'
    END AS ContributorLevel
FROM UserBadgeStats ubs
FULL OUTER JOIN PostAnalytics pa ON ubs.UserId = pa.OwnerUserId
WHERE (ubs.TotalBadges > 0 OR pa.TotalPosts > 0)
    AND (pa.MaxPostScore > 10 OR ubs.TotalBadges > 5)
ORDER BY CompositeStat DESC
LIMIT 1000;