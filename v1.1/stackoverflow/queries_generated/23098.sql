-- {"query": "23098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1120} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS PostCount, 
        SUM(COALESCE(p.Score, 0) * CASE WHEN p.PostTypeId = 1 THEN 2 ELSE 1 END) AS WeightedScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5
),
UserBadges AS (
    SELECT 
        b.UserId, 
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgePoints,
        COUNT(*) AS TotalBadges,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
TopPosts AS (
    SELECT 
        p.Id, 
        p.OwnerUserId, 
        p.Score, 
        p.ViewCount, 
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
LinkedTags AS (
    SELECT 
        pl.PostId, 
        STRING_AGG(t.TagName, ', ' ORDER BY t.Count DESC) AS TagList
    FROM PostLinks pl
    INNER JOIN Posts po ON pl.RelatedPostId = po.Id
    CROSS JOIN LATERAL string_to_array(substring(po.Tags, 2, length(po.Tags)-2), '><') AS tag_array(tag)
    INNER JOIN Tags t ON t.TagName = tag_array.tag
    WHERE pl.LinkTypeId = 3  -- Duplicates
    GROUP BY pl.PostId
    HAVING COUNT(DISTINCT t.Id) > 1
)
SELECT 
    au.Id, 
    au.DisplayName, 
    au.WeightedScore, 
    ub.BadgePoints, 
    ub.BadgeRank,
    tp.PositiveComments,
    COALESCE(tp.PreviousScore, 0) - COALESCE(tp.NextViewCount, 0) AS ScoreViewDiff,
    NULLIF(lt.TagList, '') AS CleanTagList,
    CASE 
        WHEN au.LastPostDate > CURRENT_DATE - INTERVAL '1 year' THEN 'Active' 
        WHEN au.LastPostDate IS NULL THEN 'Inactive' 
        ELSE 'Dormant' 
    END AS ActivityStatus,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = tp.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AvgBounty
FROM ActiveUsers au
LEFT OUTER JOIN UserBadges ub ON au.Id = ub.UserId
INNER JOIN TopPosts tp ON au.Id = tp.OwnerUserId AND tp.Score = (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = au.Id)
LEFT JOIN LinkedTags lt ON tp.Id = lt.PostId
WHERE au.WeightedScore > 100 OR ub.BadgePoints > 10
UNION ALL
SELECT 
    au.Id, 
    au.DisplayName || ' (High Rep)', 
    au.WeightedScore * 2, 
    ub.BadgePoints, 
    ub.BadgeRank,
    tp.PositiveComments,
    COALESCE(tp.PreviousScore, 0) + COALESCE(tp.NextViewCount, 0) AS ScoreViewSum,
    UPPER(lt.TagList),
    'HighRep' AS ActivityStatus,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = au.Id) AND v.VoteTypeId = 9) AS TotalClosedBounty
FROM ActiveUsers au
LEFT OUTER JOIN UserBadges ub ON au.Id = ub.UserId
INNER JOIN TopPosts tp ON au.Id = tp.OwnerUserId
LEFT JOIN LinkedTags lt ON tp.Id = lt.PostId
WHERE au.Reputation > 10000
INTERSECT
SELECT 
    au.Id, 
    au.DisplayName, 
    au.WeightedScore, 
    ub.BadgePoints, 
    ub.BadgeRank,
    tp.PositiveComments,
    0 AS ScoreViewDiff,
    lt.TagList,
    'Intersect' AS ActivityStatus,
    0 AS AvgBounty
FROM ActiveUsers au
INNER JOIN UserBadges ub ON au.Id = ub.UserId AND ub.TotalBadges > 5
INNER JOIN TopPosts tp ON au.Id = tp.OwnerUserId
LEFT JOIN LinkedTags lt ON tp.Id = lt.PostId
WHERE EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = tp.Id AND ph.PostHistoryTypeId IN (10, 11) AND ph.CreationDate > au.LastPostDate);
