-- {"query": "23036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 842} 

WITH TopTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        AVG(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS AvgScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViews,
        STRING_AGG(CASE WHEN p.Tags IS NOT NULL THEN substring(p.Tags, 2, length(p.Tags)-2) ELSE '' END, ', ') AS AllTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge
    FROM Badges b
    GROUP BY b.UserId
),
CorrelatedVotes AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = v.PostId AND v2.VoteTypeId = 8 AND v2.BountyAmount IS NOT NULL) AS AvgBounty
    FROM Votes v
    GROUP BY v.PostId
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.AvgScore,
    ups.TotalViews,
    ups.AllTags,
    COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
    COALESCE(ubs.HasGoldBadge, 0) AS HasGoldBadge,
    tt.TagName AS TopTag,
    tt.TagRank,
    cv.VoteCount,
    COALESCE(cv.AvgBounty, 0) AS AvgBounty,
    RANK() OVER (PARTITION BY tt.TagName ORDER BY ups.TotalViews DESC) AS ViewRankPerTag,
    CASE 
        WHEN ups.TotalViews > 100000 THEN 'High View User'
        WHEN ups.TotalViews BETWEEN 10000 AND 100000 THEN 'Medium View User'
        ELSE 'Low View User'
    END AS ViewCategory
FROM UserPostStats ups
LEFT OUTER JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
INNER JOIN Posts p ON ups.UserId = p.OwnerUserId
LEFT OUTER JOIN CorrelatedVotes cv ON p.Id = cv.PostId
CROSS JOIN TopTags tt
WHERE ups.Reputation > 1000
  AND (p.Tags LIKE '%' || tt.TagName || '%' OR p.Tags IS NULL)
  AND EXISTS (
      SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5
  )
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS TotalPosts,
    0 AS AvgScore,
    0 AS TotalViews,
    '' AS AllTags,
    COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
    COALESCE(ubs.HasGoldBadge, 0) AS HasGoldBadge,
    NULL AS TopTag,
    NULL AS TagRank,
    0 AS VoteCount,
    0 AS AvgBounty,
    NULL AS ViewRankPerTag,
    'No Posts' AS ViewCategory
FROM Users u
LEFT OUTER JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
WHERE u.Reputation > 1000
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY Reputation DESC
LIMIT 1000;
