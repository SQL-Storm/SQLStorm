-- {"query": "15047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 550}
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY COUNT(DISTINCT p.Id) DESC) AS YearlyPostRank,
        AVG(NULLIF(p.ViewCount, 0)) OVER (PARTITION BY u.Location) AS AvgLocationViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100 AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Location
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalPostScore,
    tp.TagName AS MostPopularTag,
    tp.PostCount AS TagPostCount,
    CASE 
        WHEN ups.YearlyPostRank <= 10 THEN 'Top Contributor'
        WHEN ups.TotalPostScore > 100 THEN 'Highly Rated'
        ELSE 'Regular User'
    END AS UserCategory,
    ROUND(100.0 * ups.TotalPosts / (SELECT COUNT(*) FROM Posts), 2) AS PostPercentile,
    ups.AvgLocationViews
FROM UserPostStats ups
JOIN TagPopularity tp ON tp.PostCount = (
    SELECT MAX(PostCount)
    FROM TagPopularity
)
WHERE ups.TotalPosts > 5
ORDER BY ups.TotalPostScore DESC
LIMIT 100;
