-- {"query": "2042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 765} 
WITH UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostStatistics AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS AcceptedAnswers
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId, p.PostTypeId
),
ActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        (SELECT COUNT(DISTINCT po.Id) FROM Posts po WHERE po.OwnerUserId = u.Id AND po.CreationDate > cast('2024-10-01' as date) - INTERVAL '365 days') AS RecentPosts,
        (SELECT COUNT(DISTINCT co.Id) FROM Comments co WHERE co.UserId = u.Id AND co.CreationDate > cast('2024-10-01' as date) - INTERVAL '365 days') AS RecentComments
    FROM Users u
),
TopContributors AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ps1.TotalViews, 0) + COALESCE(ps2.TotalViews, 0) AS TotalViews,
        COALESCE(ps1.AvgScore, 0) + COALESCE(ps2.AvgScore, 0) AS TotalAvgScore,
        COALESCE(ps1.AcceptedAnswers, 0) + COALESCE(ps2.AcceptedAnswers, 0) AS AcceptedAnswers,
        COALESCE(ua.GoldBadges, 0) AS GoldBadges,
        COALESCE(ua.SilverBadges, 0) AS SilverBadges,
        COALESCE(ua.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(aa.RecentPosts, 0) AS RecentPosts,
        COALESCE(aa.RecentComments, 0) AS RecentComments
    FROM Users u
    LEFT JOIN UserBadges ua ON u.Id = ua.UserId
    LEFT JOIN PostStatistics ps1 ON u.Id = ps1.OwnerUserId AND ps1.PostTypeId = 1
    LEFT JOIN PostStatistics ps2 ON u.Id = ps2.OwnerUserId AND ps2.PostTypeId = 2
    LEFT JOIN ActiveUsers aa ON u.Id = aa.Id
    WHERE COALESCE(ps1.TotalViews, 0) + COALESCE(ps2.TotalViews, 0) > 10000
      AND COALESCE(ua.GoldBadges, 0) > 0
      AND COALESCE(aa.RecentPosts, 0) > 10
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalViews,
    tc.TotalAvgScore,
    tc.AcceptedAnswers,
    tc.GoldBadges,
    tc.SilverBadges,
    tc.BronzeBadges,
    tc.RecentPosts,
    tc.RecentComments
FROM TopContributors tc
ORDER BY tc.TotalViews DESC, tc.GoldBadges DESC, tc.RecentPosts DESC;