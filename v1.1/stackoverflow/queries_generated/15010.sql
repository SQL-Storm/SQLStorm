-- {"query": "15010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 25685, "output_tokens": 7743} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS GoldBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS ExactGoldBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(b.Id) DESC) AS LocationBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.Location IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Location
),
PostInteractions AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadges,
    pi.TotalVotes,
    pi.TotalComments,
    pi.AveragePostScore,
    COALESCE(pi.MaxViewCount, 0) AS MaxPostViews,
    CASE 
        WHEN ubc.LocationBadgeRank = 1 THEN 'Top Badge Earner in Location'
        ELSE 'Other Contributor'
    END AS LocationStatus,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (
         SELECT p.Id 
         FROM Posts p 
         WHERE p.OwnerUserId = ubc.UserId
     )) AS RelatedPostLinks
FROM UserBadgeCounts ubc
JOIN PostInteractions pi ON ubc.UserId = pi.OwnerUserId
WHERE ubc.ExactGoldBadges > 5
    AND (pi.TotalVotes > 100 OR pi.TotalComments > 50)
ORDER BY 
    ubc.GoldBadges DESC, 
    pi.AveragePostScore DESC
LIMIT 100;