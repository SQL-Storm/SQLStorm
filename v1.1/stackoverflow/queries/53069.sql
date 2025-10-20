WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATE '2010-01-01' AND p.CreationDate < DATE '2020-01-01'
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 100
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS TaggedPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY t.Id, t.TagName
    ORDER BY TaggedPosts DESC
    LIMIT 10
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
PostHistoryMetrics AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
),
LinkedPosts AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
    GROUP BY pl.PostId
),
UserTagAggregates AS (
    SELECT
        ua.UserId,
        tp.TagId,
        tp.TagName,
        tp.TaggedPosts,
        tp.Upvotes,
        ua.TotalScore,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ca.TotalComments, 0) AS TotalComments,
        ca.AvgCommentScore,
        SUM(COALESCE(phm.EditCount, 0)) AS TotalEditsOnPosts,
        AVG(COALESCE(lp.LinkedCount, 0)) AS AvgLinkedCount
    FROM UserActivity ua
    JOIN Users u ON ua.UserId = u.Id
    LEFT JOIN BadgeCounts bc ON ua.UserId = bc.UserId
    LEFT JOIN CommentActivity ca ON ua.UserId = ca.UserId
    CROSS JOIN TagPopularity tp
    JOIN Posts p ON ua.UserId = p.OwnerUserId AND p.Tags LIKE '%' || tp.TagName || '%'
    LEFT JOIN PostHistoryMetrics phm ON p.Id = phm.PostId
    LEFT JOIN LinkedPosts lp ON p.Id = lp.PostId
    WHERE ua.Reputation > 10000
    GROUP BY
        ua.UserId,
        tp.TagId,
        tp.TagName,
        tp.TaggedPosts,
        tp.Upvotes,
        ua.TotalScore,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        ca.TotalComments,
        ca.AvgCommentScore
)
SELECT
    uta.UserId,
    u.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.TotalScore,
    ua.TotalViews,
    ua.AvgScore,
    uta.GoldBadges,
    uta.SilverBadges,
    uta.BronzeBadges,
    uta.TotalComments,
    uta.AvgCommentScore,
    uta.TagName AS TopTag,
    uta.TaggedPosts,
    uta.Upvotes,
    uta.TotalEditsOnPosts,
    uta.AvgLinkedCount,
    -- compute rank per tag using a separate window in a derived query
    r.RankInTag,
    uv.UserUpvotesGiven
FROM UserTagAggregates uta
JOIN Users u ON uta.UserId = u.Id
JOIN UserActivity ua ON uta.UserId = ua.UserId
LEFT JOIN (
    SELECT
        UserId,
        TagId,
        ROW_NUMBER() OVER (PARTITION BY TagId ORDER BY TotalScore DESC) AS RankInTag
    FROM (
        SELECT ua.UserId, tp.TagId, SUM(p.Score) AS TotalScore
        FROM UserActivity ua
        CROSS JOIN TagPopularity tp
        JOIN Posts p ON ua.UserId = p.OwnerUserId AND p.Tags LIKE '%' || tp.TagName || '%'
        GROUP BY ua.UserId, tp.TagId
    ) t
) r ON r.UserId = uta.UserId AND r.TagId = uta.TagId
LEFT JOIN (
    SELECT v.UserId, COUNT(*) AS UserUpvotesGiven
    FROM Votes v
    WHERE v.VoteTypeId = 2
    GROUP BY v.UserId
) uv ON uv.UserId = uta.UserId
WHERE uta.TotalEditsOnPosts > 10
  AND uta.AvgLinkedCount > 5
ORDER BY ua.TotalScore DESC, uta.Upvotes DESC
LIMIT 100;