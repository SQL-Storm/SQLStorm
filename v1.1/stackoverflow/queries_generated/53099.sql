-- {"query": "53099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1022} 

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
    AND p.CreationDate BETWEEN '2015-01-01' AND '2023-01-01'
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
        v.PostId,
        p.OwnerUserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate > '2010-01-01'
    GROUP BY v.PostId, p.OwnerUserId
),
TagMetrics AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.Score) AS TotalTagScore
    FROM Tags t
    INNER JOIN Posts p ON p.PostTypeId = 1 AND strpos(p.Tags, '<' || t.TagName || '>') > 0
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
        SUM(vm.Upvotes) AS TotalUpvotes,
        SUM(vm.Downvotes) AS TotalDownvotes,
        COUNT(DISTINCT tm.TagId) AS UniqueTagsEngaged,
        AVG(em.EditCount) AS AvgEditsPerPost
    FROM UserHierarchy uh
    LEFT JOIN PostMetrics pm ON uh.Id = pm.OwnerUserId
    LEFT JOIN BadgeMetrics bm ON uh.Id = bm.UserId
    LEFT JOIN VoteMetrics vm ON uh.Id = vm.OwnerUserId
    LEFT JOIN Posts p ON uh.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN TagMetrics tm ON strpos(p.Tags, '<' || tm.TagName || '>') > 0
    LEFT JOIN EditMetrics em ON p.Id = em.PostId
    GROUP BY 
        uh.Id, uh.DisplayName, uh.Reputation, uh.Level,
        pm.TotalPosts, pm.AvgScore, pm.TotalViews, pm.LastPostDate,
        bm.GoldBadges, bm.SilverBadges, bm.BronzeBadges
)
SELECT 
    *,
    RANK() OVER (PARTITION BY Level ORDER BY Reputation DESC, TotalUpvotes DESC) AS RankInLevel,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY AvgScore) OVER (PARTITION BY Level) AS MedianScoreInLevel
FROM CombinedStats
WHERE TotalPosts > 100 AND GoldBadges >= 3
ORDER BY Level ASC, RankInLevel ASC
LIMIT 1000;
