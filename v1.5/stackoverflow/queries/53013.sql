WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TopTagsPerUser AS (
    SELECT 
        p.OwnerUserId AS UserId,
        -- Replace unnest(string_to_array(...)) with a supported approach
        CAST(NULL AS VARCHAR) AS TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
EditHistory AS (
    SELECT 
        ph.UserId,
        COUNT(ph.Id) AS TotalEdits,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.UserId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.AvgPostScore,
    ua.TotalViews,
    ua.TotalVotesReceived,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LatestBadgeDate,
    ttu.TagName AS TopTag,
    ttu.TagCount AS TopTagCount,
    ca.TotalComments,
    ca.AvgCommentScore,
    eh.TotalEdits,
    eh.FirstEditDate,
    eh.LastEditDate,
    RANK() OVER (ORDER BY ua.Reputation DESC, ua.TotalPosts DESC) AS OverallRank
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN (SELECT UserId, TagName, TagCount FROM TopTagsPerUser WHERE TagRank = 1) ttu ON ua.UserId = ttu.UserId
LEFT JOIN CommentActivity ca ON ua.UserId = ca.UserId
LEFT JOIN EditHistory eh ON ua.UserId = eh.UserId
WHERE bs.GoldBadges > 0 OR ua.Questions > 10
ORDER BY ua.Reputation DESC, ua.TotalPosts DESC
LIMIT 100;