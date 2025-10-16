WITH PostRanks AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        -- compute median views by year using a percentile_cont window aggregated per year via subquery join
        EXTRACT(YEAR FROM p.CreationDate) AS CreationYear
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.Score > 0 
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
),
MedianViewsByYear AS (
    SELECT
        CreationYear,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) AS MedianViews
    FROM PostRanks
    GROUP BY CreationYear
),
UserBadgeCounts AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    pr.Id,
    pr.Title,
    pr.Score,
    pr.DisplayName,
    pr.Reputation,
    pr.ScoreRank,
    mv.MedianViews AS MedianViewsByYear,
    COALESCE(ubc.TotalBadges, 0) AS UserBadgeCount,
    COALESCE(ubc.GoldBadges, 0) AS UserGoldBadges,
    CASE 
        WHEN pr.AnswerCount > 10 THEN 'High Engagement'
        WHEN pr.AnswerCount BETWEEN 5 AND 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pr.Id) AS CommentCount
FROM PostRanks pr
LEFT JOIN MedianViewsByYear mv ON pr.CreationYear = mv.CreationYear
LEFT JOIN UserBadgeCounts ubc ON pr.OwnerUserId = ubc.UserId
WHERE pr.ScoreRank <= 100 
  AND (pr.Reputation > 1000 OR COALESCE(ubc.GoldBadges, 0) > 0)
GROUP BY
    pr.Id,
    pr.Title,
    pr.Score,
    pr.DisplayName,
    pr.Reputation,
    pr.ScoreRank,
    mv.MedianViews,
    ubc.TotalBadges,
    ubc.GoldBadges,
    pr.AnswerCount,
    pr.CreationYear
ORDER BY pr.Score DESC, pr.Reputation DESC
LIMIT 50;