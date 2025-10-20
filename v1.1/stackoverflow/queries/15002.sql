-- {"query": "15002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 7005, "output_tokens": 1979} 
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
PostActivityMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
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
    pam.TotalPosts,
    pam.QuestionCount,
    pam.AnswerCount,
    pam.AvgPostScore,
    pam.MaxViewCount,
    pam.TotalVotes,
    COALESCE(pam.AvgPostScore, 0) * SQRT(COALESCE(ubs.TotalBadges, 1)) AS ComplexScore,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ubs.UserId)) AS RelatedPostLinks
FROM UserBadgeStats ubs
JOIN PostActivityMetrics pam ON ubs.UserId = pam.OwnerUserId
WHERE 
    ubs.TotalBadges > 0 
    AND pam.TotalPosts > 5
    AND (pam.AvgPostScore > 1 OR ubs.GoldBadges > 0)
ORDER BY ComplexScore DESC
LIMIT 100;