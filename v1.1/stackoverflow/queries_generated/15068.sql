-- {"query": "15068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 161115, "output_tokens": 47297} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgViewCount,
        FIRST_VALUE(p.Title) OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS TopPostTitle,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        UNNEST(STRING_TO_ARRAY(TRIM(p.Tags, '><'), '><')) AS TagName,
        COUNT(*) AS TagFrequency,
        ROUND(AVG(p.Score), 2) AS AvgTagScore
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY TagName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalPostScore,
    ups.AvgViewCount,
    ups.TopPostTitle,
    ups.PostCountRank,
    (
        SELECT STRING_AGG(tp.TagName, ', ' ORDER BY tp.TagFrequency DESC)
        FROM TagPopularity tp
        WHERE tp.TagFrequency > 100
        LIMIT 3
    ) AS TopTags,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = ups.UserId AND b.Class = 1), 0
    ) AS GoldBadgeCount,
    CASE 
        WHEN ups.TotalPosts = 0 THEN 0
        ELSE ROUND(ups.TotalPostScore * 1.0 / ups.TotalPosts, 2)
    END AS AvgPostScore
FROM UserPostStats ups
WHERE ups.TotalPosts > 5
    AND (
        ups.AvgViewCount > (SELECT AVG(ViewCount) FROM Posts)
        OR ups.TotalPostScore > 100
    )
ORDER BY ups.TotalPostScore DESC, ups.TotalPosts DESC
LIMIT 100;