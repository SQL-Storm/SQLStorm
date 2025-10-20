-- {"query": "23063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 846} 
WITH GoldBadgeUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS GoldBadgeCount,
        STRING_AGG(b.Name, ', ') AS GoldBadges
    FROM Users u
    INNER JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class = 1 AND b.TagBased = TRUE
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 1
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Score,
        COALESCE(p.FavoriteCount, 0) AS Favorites,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 1000
),
UserActivity AS (
    SELECT 
        gbu.UserId,
        gbu.DisplayName,
        gbu.Reputation,
        gbu.GoldBadgeCount,
        gbu.GoldBadges,
        tq.PostId,
        tq.Title,
        tq.ViewCount,
        tq.Score,
        tq.Favorites,
        (SELECT AVG(v.BountyAmount) 
         FROM Votes v 
         WHERE v.PostId = tq.PostId AND v.VoteTypeId IN (8, 9) AND v.BountyAmount IS NOT NULL) AS AvgBounty,
        COALESCE((SELECT COUNT(c.Id) 
                  FROM Comments c 
                  WHERE c.PostId = tq.PostId AND c.Score > 0), 0) AS PositiveComments
    FROM GoldBadgeUsers gbu
    LEFT OUTER JOIN TopQuestions tq ON gbu.UserId = tq.OwnerUserId AND tq.ViewRank = 1
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsage,
        p.OwnerUserId,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
),
CombinedStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadgeCount,
        ua.GoldBadges,
        ua.PostId,
        ua.Title,
        ua.ViewCount,
        ua.Score,
        ua.Favorites,
        ua.AvgBounty,
        ua.PositiveComments,
        ts.TagName AS TopTag,
        ts.TagUsage,
        CASE 
            WHEN ua.ViewCount IS NULL THEN 'No Top Question'
            WHEN ua.Score > 100 THEN 'High Score: ' || CAST(ua.Score AS VARCHAR)
            ELSE 'Standard'
        END AS ScoreCategory,
        NULLIF(ua.AvgBounty, 0) AS AdjustedBounty
    FROM UserActivity ua
    LEFT OUTER JOIN TagStats ts ON ua.UserId = ts.OwnerUserId AND ts.TagRank = 1
    WHERE ua.Reputation > 10000 OR ua.GoldBadgeCount >= 3
)
SELECT * FROM CombinedStats
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS GoldBadgeCount,
    NULL AS GoldBadges,
    NULL AS PostId,
    NULL AS Title,
    NULL AS ViewCount,
    NULL AS Score,
    NULL AS Favorites,
    NULL AS AvgBounty,
    NULL AS PositiveComments,
    NULL AS TopTag,
    NULL AS TagUsage,
    'Inactive High Rep' AS ScoreCategory,
    NULL AS AdjustedBounty
FROM Users u
LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Reputation > 50000 AND p.Id IS NULL
ORDER BY Reputation DESC
LIMIT 100;