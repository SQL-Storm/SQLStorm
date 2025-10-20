WITH RECURSIVE UserHierarchy AS (
    SELECT Id, DisplayName, Reputation, 0 AS Level
    FROM Users
    WHERE Reputation > 100000
    UNION ALL
    SELECT u.Id, u.DisplayName, u.Reputation, uh.Level + 1
    FROM Users u
    INNER JOIN UserHierarchy uh ON u.Reputation < uh.Reputation AND ABS(u.Id - uh.Id) < 1000
    WHERE uh.Level < 5
),
PostMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate BETWEEN DATE '2015-01-01' AND DATE '2023-01-01'
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) > 50
),
BadgeMetrics AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 5
),
VoteMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate > DATE '2010-01-01'
    GROUP BY p.OwnerUserId
),
TagMetrics AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalTagScore
    FROM Tags t
    INNER JOIN Posts p ON p.PostTypeId = 1 AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
EditMetrics AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.PostId
    HAVING COUNT(DISTINCT ph.Id) > 10
),
CombinedStats AS (
    SELECT 
        uh.Id AS UserId,
        uh.DisplayName,
        uh.Reputation,
        uh.Level,
        pm.TotalPosts,
        pm.AvgScore,
        pm.TotalViews,
        pm.LastPostDate,
        bm.GoldBadges,
        bm.SilverBadges,
        bm.BronzeBadges,
        COALESCE(SUM(vm.Upvotes), 0) AS TotalUpvotes,
        COALESCE(SUM(vm.Downvotes), 0) AS TotalDownvotes,
        COUNT(DISTINCT tm.TagId) AS UniqueTagsEngaged,
        AVG(em.EditCount) AS AvgEditsPerPost
    FROM UserHierarchy uh
    LEFT JOIN PostMetrics pm ON uh.Id = pm.OwnerUserId
    LEFT JOIN BadgeMetrics bm ON uh.Id = bm.UserId
    LEFT JOIN VoteMetrics vm ON uh.Id = vm.OwnerUserId
    LEFT JOIN Posts p ON uh.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN TagMetrics tm ON POSITION('<' || tm.TagName || '>' IN p.Tags) > 0
    LEFT JOIN EditMetrics em ON p.Id = em.PostId
    GROUP BY 
        uh.Id, uh.DisplayName, uh.Reputation, uh.Level,
        pm.TotalPosts, pm.AvgScore, pm.TotalViews, pm.LastPostDate,
        bm.GoldBadges, bm.SilverBadges, bm.BronzeBadges
),
MedianPerLevel AS (
    SELECT
        Level,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY AvgScore) AS MedianScoreInLevel
    FROM CombinedStats
    WHERE AvgScore IS NOT NULL
    GROUP BY Level
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.Level,
    cs.TotalPosts,
    cs.AvgScore,
    cs.TotalViews,
    cs.LastPostDate,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.TotalUpvotes,
    cs.TotalDownvotes,
    cs.UniqueTagsEngaged,
    cs.AvgEditsPerPost,
    RANK() OVER (PARTITION BY cs.Level ORDER BY cs.Reputation DESC, cs.TotalUpvotes DESC) AS RankInLevel,
    m.MedianScoreInLevel
FROM CombinedStats cs
LEFT JOIN MedianPerLevel m ON cs.Level = m.Level
WHERE cs.TotalPosts > 100 AND COALESCE(cs.GoldBadges, 0) >= 3
ORDER BY cs.Level ASC, RankInLevel ASC
LIMIT 1000;