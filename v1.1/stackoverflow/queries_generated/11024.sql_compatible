WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.PostTypeId, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.AnswerCount, 
        Posts.CommentCount, 
        Posts.OwnerUserId,
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation AS OwnerReputation
    FROM 
        Posts
    INNER JOIN 
        Users ON Posts.OwnerUserId = Users.Id
    WHERE 
        Posts.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
),
UserActivity AS (
    SELECT 
        Posts.OwnerUserId AS UserId, 
        COUNT(*) AS TotalPosts, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(Posts.ViewCount) AS TotalViews, 
        SUM(Posts.AnswerCount) AS TotalAnswers, 
        SUM(Posts.CommentCount) AS TotalComments, 
        MAX(Posts.CreationDate) AS LastActivityDate
    FROM 
        Posts
    GROUP BY 
        Posts.OwnerUserId
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        Badges.UserId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.PostTypeId, 
    RecentPosts.Title, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    UserActivity.TotalPosts, 
    UserActivity.TotalScore, 
    UserActivity.TotalViews, 
    UserActivity.TotalAnswers, 
    UserActivity.TotalComments, 
    UserActivity.LastActivityDate, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
WHERE 
    RecentPosts.Score > (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1)
    AND RecentPosts.ViewCount > (SELECT AVG(p.ViewCount) FROM Posts p WHERE p.PostTypeId = 1)
ORDER BY 
    RecentPosts.Score DESC, 
    RecentPosts.ViewCount DESC, 
    RecentPosts.CreationDate DESC
LIMIT 10;