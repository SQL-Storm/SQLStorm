-- {"query": "15083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 196140, "output_tokens": 57701} 
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
        u.Reputation * 
        (1 + COALESCE(ups.TotalTagRelevance, 0)) * 
        GREATEST(1, LOG(ups.TotalPosts + 1)), 
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
    AND ups.TotalPosts > 5
ORDER BY CompositeReputation DESC
LIMIT 100;