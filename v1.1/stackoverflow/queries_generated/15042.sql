-- {"query": "15042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 100405, "output_tokens": 29812} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadge,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostActivityRanking AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC) AS YearlyViewRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT AVG(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS AvgVoteTime
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    ub.UserId,
    ub.DisplayName,
    ub.TotalBadges,
    ub.GoldBadge,
    par.PostId,
    par.Title,
    par.Tags,
    COALESCE(par.Score, 0) AS PostScore,
    par.ViewCount,
    par.YearlyViewRank,
    par.CommentCount,
    EXTRACT(EPOCH FROM (NOW() - par.AvgVoteTime)) / 3600 AS HoursSinceAvgVote,
    CASE 
        WHEN ub.AvgPostScore > 10 AND par.ViewCount > 1000 THEN 'High Impact'
        WHEN ub.AvgPostScore > 5 AND par.ViewCount > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory
FROM UserBadgeStats ub
JOIN PostActivityRanking par ON ub.UserId = par.PostId % 100000
WHERE 
    ub.BadgeRank <= 50 
    AND par.YearlyViewRank <= 100
    AND (
        par.Tags LIKE '%<sql>%' 
        OR par.Tags LIKE '%<database>%'
    )
ORDER BY 
    PostScore DESC, 
    ViewCount DESC
LIMIT 500;