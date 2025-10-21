-- {"query": "11066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 991} 

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
    FROM 
        Posts
    WHERE 
        Posts.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(Posts.ViewCount) AS TotalViews, 
        SUM(Posts.CommentCount) AS TotalComments
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgeCount, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        Badges.UserId
),
PostHistorySummary AS (
    SELECT 
        PostHistory.PostId, 
        COUNT(PostHistory.Id) AS HistoryCount, 
        SUM(CASE WHEN PostHistory.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedPosts, 
        SUM(CASE WHEN PostHistory.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedPosts, 
        SUM(CASE WHEN PostHistory.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletedPosts, 
        SUM(CASE WHEN PostHistory.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeletedPosts
    FROM 
        PostHistory
    GROUP BY 
        PostHistory.PostId
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
    UserActivity.DisplayName AS UserName, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.TotalViews, 
    UserActivity.TotalComments, 
    BadgeSummary.BadgeCount, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges, 
    PostHistorySummary.HistoryCount, 
    PostHistorySummary.ClosedPosts, 
    PostHistorySummary.ReopenedPosts, 
    PostHistorySummary.DeletedPosts, 
    PostHistorySummary.UndeletedPosts
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
LEFT JOIN 
    PostHistorySummary ON RecentPosts.Id = PostHistorySummary.PostId
ORDER BY 
    RecentPosts.CreationDate DESC;
