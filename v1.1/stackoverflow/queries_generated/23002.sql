-- {"query": "23002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 844} 

WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        COALESCE((SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 0) AS AvgQuestionScore
    FROM Users u
    WHERE u.Reputation > 1000
    AND u.CreationDate >= '2010-01-01'
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ' ORDER BY b.Date DESC) AS GoldBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(b.Id) > 5
),
ActivePosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.ViewCount,
        p.Score,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        NULLIF(p.Tags, '') AS Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate BETWEEN '2020-01-01' AND CURRENT_DATE
    AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
),
MergedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.ReputationRank,
        tu.AvgQuestionScore,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        ub.GoldBadges,
        ap.PostId,
        ap.Title,
        ap.ViewCount,
        ap.Score,
        ap.PreviousScore,
        ap.Tags,
        ap.PositiveComments,
        CASE 
            WHEN ap.Score > ap.PreviousScore THEN 'Improved'
            WHEN ap.Score < ap.PreviousScore THEN 'Declined'
            ELSE 'Stable'
        END AS ScoreTrend,
        COALESCE((SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = ap.PostId AND ph.PostHistoryTypeId IN (4,5,6)), ap.CreationDate) AS LastEdit
    FROM TopUsers tu
    LEFT OUTER JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT OUTER JOIN ActivePosts ap ON tu.UserId = ap.OwnerUserId
    WHERE tu.ReputationRank <= 100
    OR ap.ViewCount > 10000
)
SELECT 
    md.UserId,
    md.DisplayName,
    md.Reputation,
    md.BadgeCount,
    md.GoldBadges,
    md.PostId,
    md.Title,
    md.ViewCount,
    md.Score,
    md.ScoreTrend,
    md.LastEdit,
    RANK() OVER (PARTITION BY md.UserId ORDER BY md.ViewCount DESC) AS PostRank,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags t WHERE t.Count > 100 AND md.Tags LIKE '%' || t.TagName || '%') AS PopularTags
FROM MergedData md
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS BadgeCount,
    NULL AS GoldBadges,
    NULL AS PostId,
    NULL AS Title,
    0 AS ViewCount,
    0 AS Score,
    'N/A' AS ScoreTrend,
    NULL AS LastEdit,
    1 AS PostRank,
    NULL AS PopularTags
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM MergedData md WHERE md.UserId = u.Id)
AND u.Reputation BETWEEN 500 AND 1000
ORDER BY Reputation DESC;
