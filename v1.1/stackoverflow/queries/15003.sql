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
      AND p.PostTypeId IN (1, 2)
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
),
MostUsedTagPerUser AS (
    SELECT ups.UserId,
           tp.TagName,
           tp.TagCount
    FROM UserPostStats ups
    CROSS JOIN LATERAL (
        SELECT tp2.TagName, tp2.TagCount
        FROM TagPopularity tp2
        WHERE tp2.TagCount > 10
        ORDER BY tp2.TagCount DESC
        LIMIT 1
    ) tp
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.AvgPostScore,
    mut.TagName AS MostUsedTag,
    mut.TagCount,
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
LEFT JOIN MostUsedTagPerUser mut ON mut.UserId = ups.UserId
LEFT JOIN (
    SELECT UserId, 
           COUNT(*) AS UpvoteCount
    FROM Votes 
    WHERE VoteTypeId = 2
    GROUP BY UserId
) v ON v.UserId = ups.UserId
WHERE ups.TotalPosts > 5
  AND ups.PostCountRank <= 100
GROUP BY
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.AvgPostScore,
    mut.TagName,
    mut.TagCount,
    v.UpvoteCount,
    ups.PostCountRank
ORDER BY ups.AvgPostScore DESC, ups.TotalPosts DESC
LIMIT 50;