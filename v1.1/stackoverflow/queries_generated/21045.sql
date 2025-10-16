-- {"query": "21045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1224} 

WITH 
RecentUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
      AND u.Location IS NOT NULL
      AND LENGTH(u.Location) > 5
),
HighActivityPosts AS (
    SELECT p.Id as PostId, p.OwnerUserId, p.Title, p.Score, p.ViewCount,
           COUNT(c.Id) as CommentCount,
           AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount > 0) as AvgBounty
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id AND c.Score > 0
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (8, 9) -- Bounty related
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
      AND p.Score >= 5
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount
    HAVING COUNT(c.Id) > 3 OR p.ViewCount > 1000
),
TagStats AS (
    SELECT t.TagName,
           COUNT(CASE WHEN p.Score > 0 THEN 1 END) as PositivePosts,
           SUM(p.ViewCount) as TotalViews,
           STRING_AGG(DISTINCT SUBSTRING(p.Title, 1, 50), ' | ') as SampleTitles
    FROM Tags t
    INNER JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0
    WHERE t.Count > 50
      AND p.PostTypeId = 1
    GROUP BY t.TagName
),
UserAchievements AS (
    SELECT ru.Id,
           COALESCE(b.GoldCount, 0) as GoldBadges,
           COALESCE(b.SilverCount, 0) as SilverBadges,
           hap.CommentCount,
           hap.AvgBounty
    FROM RecentUsers ru
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) as GoldCount,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) as SilverCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = ru.Id
    LEFT JOIN HighActivityPosts hap ON hap.OwnerUserId = ru.Id
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    ru.RepRank,
    COALESCE(ua.GoldBadges, 0) as GoldBadges,
    COALESCE(ua.SilverBadges, 0) as SilverBadges,
    hap.Title as TopPostTitle,
    hap.ViewCount as PostViews,
    hap.CommentCount,
    COALESCE(hap.AvgBounty, 0) as AvgBountyAwarded,
    ts.TagName as PrimaryTag,
    ts.TotalViews as TagTotalViews,
    CASE 
        WHEN ua.GoldBadges >= 3 THEN 'Elite'
        WHEN ua.SilverBadges >= 10 OR ru.Reputation >= 5000 THEN 'Veteran'
        WHEN hap.CommentCount >= 20 THEN 'Active'
        ELSE 'Newcomer'
    END as UserTier,
    CONCAT(
        COALESCE(ts.SampleTitles, 'No tagged posts'),
        CASE WHEN hap.CommentCount > 15 THEN ' | High engagement' ELSE '' END,
        CASE WHEN ru.Location LIKE '%USA%' THEN ' | US-based' ELSE '' END
    ) as SummaryInfo,
    (ru.Reputation * 1.0 / NULLIF(ua.GoldBadges + ua.SilverBadges, 0)) as RepPerBadge
FROM RecentUsers ru
INNER JOIN UserAchievements ua ON ua.Id = ru.Id
LEFT JOIN HighActivityPosts hap ON hap.OwnerUserId = ru.Id
LEFT JOIN (
    SELECT PostId, TagName,
           ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY ts.TotalViews DESC) as rn
    FROM TagStats ts
    INNER JOIN Posts p ON POSITION(ts.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1
) ts ON ts.PostId = hap.PostId AND ts.rn = 1
WHERE ru.RepRank <= 100  -- Top 100 recent users by reputation
  AND (ua.GoldBadges > 0 OR hap.ViewCount > 5000 OR ua.CommentCount > 10)
UNION ALL
SELECT 
    'Community Aggregate' as DisplayName,
    SUM(ru.Reputation) as Reputation,
    0 as RepRank,
    SUM(COALESCE(ua.GoldBadges, 0)) as GoldBadges,
    SUM(COALESCE(ua.SilverBadges, 0)) as SilverBadges,
    NULL as TopPostTitle,
    SUM(COALESCE(hap.ViewCount, 0)) as PostViews,
    SUM(COALESCE(hap.CommentCount, 0)) as CommentCount,
    AVG(COALESCE(hap.AvgBounty, 0)) as AvgBountyAwarded,
    NULL as PrimaryTag,
    NULL as TagTotalViews,
    'Aggregate' as UserTier,
    CONCAT('Total users: ', COUNT(*), ' | Avg rep: ', ROUND(AVG(ru.Reputation), 0)) as SummaryInfo,
    AVG(ru.Reputation * 1.0 / NULLIF(ua.GoldBadges + ua.SilverBadges, 0)) as RepPerBadge
FROM RecentUsers ru
INNER JOIN UserAchievements ua ON ua.Id = ru.Id
LEFT JOIN HighActivityPosts hap ON hap.OwnerUserId = ru.Id
WHERE ru.RepRank <= 100;
