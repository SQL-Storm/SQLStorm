WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 100 
        AND p.PostTypeId IN (1, 2)
    GROUP BY 
        u.Id, u.DisplayName
),
TopPostTags AS (
    SELECT 
        p.Id,
        UNNEST(string_to_array(substring(p.Tags, 2, NULL), '><')) AS Tag,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY UNNEST(string_to_array(substring(p.Tags, 2, NULL), '><')) ORDER BY p.Score DESC) AS TagScoreRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.AvgPostScore,
    tpt.Tag AS TopTag,
    tpt.Score AS TopTagScore,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = ubs.UserId 
       AND c.Score > 0
    ) AS PositiveCommentCount,
    COALESCE(
        (SELECT MIN(pl.CreationDate)
         FROM PostLinks pl
         JOIN Posts p ON pl.RelatedPostId = p.Id
         WHERE p.OwnerUserId = ubs.UserId 
           AND pl.LinkTypeId = 3), 
        TIMESTAMP '1970-01-01'
    ) AS EarliestDuplicateLink
FROM 
    UserBadgeStats ubs
JOIN 
    TopPostTags tpt ON tpt.TagScoreRank = 1
WHERE 
    ubs.PostCountRank <= 100
    AND ubs.AvgPostScore > 
        (SELECT AVG(Score) 
         FROM Posts 
         WHERE PostTypeId IN (1, 2))
ORDER BY 
    ubs.TotalBadges DESC, 
    ubs.AvgPostScore DESC
LIMIT 50;