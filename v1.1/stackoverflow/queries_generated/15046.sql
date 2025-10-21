-- {"query": "15046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 662}
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostCountRank,
        FIRST_VALUE(p.Title) OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS TopScoringPostTitle
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgTagScore
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY Tag
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalPostScore,
    ups.AvgViewCount,
    ups.PostCountRank,
    ups.TopScoringPostTitle,
    (SELECT STRING_AGG(tp.Tag || ':' || tp.TagCount, ', ' ORDER BY tp.TagCount DESC)
     FROM TagPopularity tp
     WHERE tp.TagCount > 10
     LIMIT 5) AS TopTags,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = ups.UserId AND b.Class = 1) AS GoldBadgeCount,
    CASE 
        WHEN ups.TotalPosts > 0 THEN ROUND(ups.TotalPostScore * 1.0 / ups.TotalPosts, 2)
        ELSE 0 
    END AS AvgPostScore,
    NULLIF(ups.AvgViewCount, 0) AS NormalizedViewCount
FROM UserPostStats ups
WHERE ups.TotalPosts > 5
    AND EXISTS (
        SELECT 1 
        FROM Votes v 
        JOIN Posts p ON v.PostId = p.Id 
        WHERE p.OwnerUserId = ups.UserId 
        AND v.VoteTypeId = 2 
        AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    )
ORDER BY ups.TotalPostScore DESC, ups.PostCountRank
LIMIT 100;
