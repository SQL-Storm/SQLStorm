WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagCount,
        SUM(p.ViewCount) AS TotalViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.AvgPostScore,
    tp.TagName AS MostUsedTag,
    tp.TagCount,
    COALESCE(v.UpvoteCount, 0) AS TotalUpvotes,
    CASE 
        WHEN ups.AvgPostScore > 10 THEN 'High Impact'
        WHEN ups.AvgPostScore > 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ContributionTier,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = ups.UserId 
       AND b.Class = 1) AS GoldBadgeCount
FROM UserPostStats ups
LEFT JOIN (
    SELECT TagName, TagCount
    FROM (
        SELECT TagName, TagCount,
               ROW_NUMBER() OVER (ORDER BY TagCount DESC, TagName ASC) AS rn
        FROM TagPopularity
        WHERE TagCount > 10
    ) t
    WHERE t.rn = 1
) tp ON 1 = 1
LEFT JOIN (
    SELECT UserId, 
           COUNT(*) AS UpvoteCount
    FROM Votes 
    WHERE VoteTypeId = 2
    GROUP BY UserId
) v ON v.UserId = ups.UserId
WHERE ups.TotalPosts > 5
  AND ups.PostCountRank <= 100
ORDER BY ups.AvgPostScore DESC, ups.TotalPosts DESC
LIMIT 50;