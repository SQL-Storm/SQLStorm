WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
),
VoteStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count
),
TopUsersPerTag AS (
    SELECT 
        t.Id AS TagId,
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS PostsInTag,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY COUNT(p.Id) DESC) AS Rank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY t.Id, p.OwnerUserId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.TotalPosts,
    us.TotalScore,
    us.AvgViewCount,
    bs.GoldBadges,
    vs.Upvotes,
    vs.Downvotes,
    tp.TagName,
    tut.PostsInTag
FROM UserStats us
LEFT JOIN BadgeStats bs ON us.UserId = bs.UserId
LEFT JOIN VoteStats vs ON us.UserId = vs.UserId
JOIN TopUsersPerTag tut ON us.UserId = tut.UserId AND tut.Rank = 1
JOIN TagPopularity tp ON tut.TagId = tp.TagId
WHERE us.Reputation > 10000
ORDER BY us.TotalScore DESC
LIMIT 100;