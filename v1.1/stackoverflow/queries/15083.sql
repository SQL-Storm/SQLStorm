WITH RankedUserPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Score, 
        p.Tags,
        u.Reputation,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostScoreRank,
        CASE 
            WHEN p.Tags LIKE '%<sql>%' THEN 1 
            WHEN p.Tags LIKE '%<database>%' THEN 0.5 
            ELSE 0 
        END AS TagRelevanceScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
), 
UserPostStats AS (
    SELECT 
        OwnerUserId,
        COUNT(*) AS TotalPosts,
        AVG(Score) AS AvgPostScore,
        MAX(PostScoreRank) AS MaxPostScoreRank,
        SUM(TagRelevanceScore) AS TotalTagRelevance
    FROM RankedUserPosts
    GROUP BY OwnerUserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    ups.TotalPosts,
    ups.AvgPostScore,
    ups.MaxPostScoreRank,
    ups.TotalTagRelevance,
    COALESCE(b.GoldBadgeCount, 0) AS GoldBadgeCount,
    ROUND(
        CAST(u.Reputation AS NUMERIC) * 
        (1 + COALESCE(ups.TotalTagRelevance, 0)) * 
        GREATEST(1, LN(CAST(COALESCE(ups.TotalPosts, 0) + 1 AS NUMERIC))), 
        2
    ) AS CompositeReputation,
    CASE 
        WHEN u.Location IS NOT NULL THEN 1 
        ELSE 0 
    END AS HasLocation
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadgeCount 
    FROM Badges 
    WHERE Class = 1 
    GROUP BY UserId
) b ON u.Id = b.UserId
WHERE 
    u.Reputation > 100 
    AND COALESCE(ups.TotalPosts, 0) > 5
GROUP BY
    u.Id,
    u.DisplayName,
    ups.TotalPosts,
    ups.AvgPostScore,
    ups.MaxPostScoreRank,
    ups.TotalTagRelevance,
    b.GoldBadgeCount,
    u.Reputation,
    u.Location
ORDER BY CompositeReputation DESC
LIMIT 100;