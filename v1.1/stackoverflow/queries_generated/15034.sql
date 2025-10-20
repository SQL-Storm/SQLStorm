-- {"query": "15034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 81725, "output_tokens": 24478} 
WITH PostRanks AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) AS MedianViewsByYear
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.Score > 0 
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
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
    pr.MedianViewsByYear,
    COALESCE(ubc.TotalBadges, 0) AS UserBadgeCount,
    COALESCE(ubc.GoldBadges, 0) AS UserGoldBadges,
    CASE 
        WHEN pr.AnswerCount > 10 THEN 'High Engagement'
        WHEN pr.AnswerCount BETWEEN 5 AND 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pr.Id) AS CommentCount
FROM PostRanks pr
LEFT JOIN UserBadgeCounts ubc ON pr.OwnerUserId = ubc.UserId
WHERE pr.ScoreRank <= 100 
  AND (pr.Reputation > 1000 OR pr.UserGoldBadges > 0)
ORDER BY pr.Score DESC, pr.Reputation DESC
LIMIT 50;