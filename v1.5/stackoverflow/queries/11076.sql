WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.PostTypeId, 
        Posts.AcceptedAnswerId, 
        Posts.ParentId, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.Body, 
        Posts.OwnerUserId, 
        Posts.OwnerDisplayName, 
        Posts.LastEditorUserId, 
        Posts.LastEditorDisplayName, 
        Posts.LastEditDate, 
        Posts.LastActivityDate, 
        Posts.Title, 
        Posts.Tags, 
        Posts.AnswerCount, 
        Posts.CommentCount, 
        Posts.FavoriteCount, 
        Posts.ClosedDate, 
        Posts.CommunityOwnedDate, 
        Posts.ContentLicense
    FROM Posts
    WHERE Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END) AS QuestionCount, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END) AS AnswerCount, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(Posts.ViewCount) AS TotalViewCount
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE Users.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY Users.Id, Users.DisplayName
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY Badges.UserId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.PostTypeId, 
    RecentPosts.AcceptedAnswerId, 
    RecentPosts.ParentId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.Body, 
    RecentPosts.OwnerUserId, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.LastEditorUserId, 
    RecentPosts.LastEditorDisplayName, 
    RecentPosts.LastEditDate, 
    RecentPosts.LastActivityDate, 
    RecentPosts.Title, 
    RecentPosts.Tags, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense, 
    COALESCE(UserActivity.DisplayName, NULL) AS DisplayName, 
    COALESCE(UserActivity.PostCount, 0) AS PostCount, 
    COALESCE(UserActivity.QuestionCount, 0) AS QuestionCount, 
    COALESCE(UserActivity.AnswerCount, 0) AS AnswerCount, 
    COALESCE(UserActivity.TotalScore, 0) AS TotalScore, 
    COALESCE(UserActivity.TotalViewCount, 0) AS TotalViewCount, 
    COALESCE(BadgeSummary.TotalBadges, 0) AS TotalBadges, 
    COALESCE(BadgeSummary.GoldBadges, 0) AS GoldBadges, 
    COALESCE(BadgeSummary.SilverBadges, 0) AS SilverBadges, 
    COALESCE(BadgeSummary.BronzeBadges, 0) AS BronzeBadges
FROM RecentPosts
LEFT JOIN UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
WHERE RecentPosts.PostTypeId = 1
GROUP BY 
    RecentPosts.Id, 
    RecentPosts.PostTypeId, 
    RecentPosts.AcceptedAnswerId, 
    RecentPosts.ParentId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.Body, 
    RecentPosts.OwnerUserId, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.LastEditorUserId, 
    RecentPosts.LastEditorDisplayName, 
    RecentPosts.LastEditDate, 
    RecentPosts.LastActivityDate, 
    RecentPosts.Title, 
    RecentPosts.Tags, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense, 
    UserActivity.DisplayName, 
    UserActivity.PostCount, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    UserActivity.TotalScore, 
    UserActivity.TotalViewCount, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges
ORDER BY RecentPosts.CreationDate DESC, COALESCE(UserActivity.TotalScore, 0) DESC
LIMIT 100;