-- {"query": "15061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 144770, "output_tokens": 42498} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostPerformance AS (
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
    pp.TotalPosts,
    pp.QuestionCount,
    pp.AnswerCount,
    pp.AvgPostScore,
    pp.MaxViewCount,
    pp.TotalVotes,
    CASE 
        WHEN pp.TotalPosts > 0 THEN ROUND(pp.TotalVotes * 1.0 / pp.TotalPosts, 2)
        ELSE NULL 
    END AS VotesPerPost,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ubs.UserId)) AS TotalLinkages,
    ubs.BadgeRank
FROM UserBadgeStats ubs
JOIN PostPerformance pp ON ubs.UserId = pp.OwnerUserId
WHERE 
    ubs.TotalBadges > 5 
    AND pp.TotalPosts > 10
    AND pp.AvgPostScore > 1
ORDER BY 
    ubs.BadgeRank, 
    pp.TotalVotes DESC
LIMIT 100;