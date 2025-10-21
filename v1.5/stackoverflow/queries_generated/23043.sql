-- {"query": "23043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 697} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalScore,
        AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionViews,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 10 OR u.Reputation > 1000
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.OwnerUserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 1) AS HighScoreComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        CONCAT(SUBSTRING(p.Title, 1, 20), '...') AS ShortTitle
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags LIKE '%sql%'
),
CombinedStats AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.ReputationRank,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        tp.PostId,
        tp.ShortTitle,
        tp.Score AS PostScore,
        (SELECT MAX(ph.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = tp.PostId 
         AND ph.PostHistoryTypeId IN (4,5,6) 
         AND ph.Comment IS NOT NULL) AS LastEditDate
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT JOIN TopPosts tp ON us.UserId = tp.OwnerUserId
    WHERE us.ReputationRank <= 100
      AND (tp.HighScoreComments > 5 OR tp.PreviousScore IS NULL)
)
SELECT * FROM CombinedStats
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    NULL AS ReputationRank,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    NULL AS PostId,
    NULL AS ShortTitle,
    SUM(PostScore) AS PostScore,
    NULL AS LastEditDate
FROM CombinedStats
ORDER BY ReputationRank NULLS LAST, GoldBadges DESC;
