WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        AVG(u.Reputation) OVER (PARTITION BY b.Class) AS AvgReputationByBadgeClass,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeCountRank,
        DENSE_RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ClassReputationRank,
        b.Class
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100 AND COALESCE(b.TagBased, FALSE) = FALSE
    GROUP BY u.Id, u.DisplayName, b.Class, u.Reputation
),
PostPerformance AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(p.Score, 0) + COALESCE(NULLIF(p.ViewCount, 0), 1) * 0.1 AS ComplexScore
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > DATE '2015-01-01'
    GROUP BY p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.AvgReputationByBadgeClass,
    pp.PostTypeId,
    MAX(pp.UpVotes) AS MaxUpVotes,
    MIN(pp.DownVotes) AS MinDownVotes,
    AVG(pp.ComplexScore) AS AvgComplexScore,
    CASE 
        WHEN SUM(pp.UpVotes) > 100 THEN 'High Impact'
        WHEN SUM(pp.UpVotes) > 50 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS UserImpactCategory
FROM UserBadgeStats ubs
JOIN PostPerformance pp ON ubs.UserId = pp.OwnerUserId
WHERE 
    ubs.BadgeCountRank <= 500
    AND pp.ComplexScore > 10
    AND (ubs.ClassReputationRank = 1 OR pp.CommentCount > 5)
GROUP BY 
    ubs.UserId, 
    ubs.DisplayName, 
    ubs.TotalBadges, 
    ubs.AvgReputationByBadgeClass,
    pp.PostTypeId,
    ubs.BadgeCountRank,
    ubs.ClassReputationRank
HAVING SUM(pp.UpVotes) > AVG(pp.DownVotes)
ORDER BY ubs.TotalBadges DESC, AvgComplexScore DESC
LIMIT 100;