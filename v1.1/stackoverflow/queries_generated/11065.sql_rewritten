-- {"query": "11065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 808} 
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
        Posts.CreationDate > cast('2024-10-01' as date) - interval '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
        SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > cast('2024-10-01' as date) - interval '365 days'
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgeCount, 
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount, 
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount, 
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Badges
    GROUP BY 
        Badges.UserId
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
    UserActivity.DisplayName AS OwnerDisplayName, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    BadgeSummary.BadgeCount, 
    BadgeSummary.GoldBadgeCount, 
    BadgeSummary.SilverBadgeCount, 
    BadgeSummary.BronzeBadgeCount
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
ORDER BY 
    RecentPosts.CreationDate DESC, 
    UserActivity.TotalScore DESC, 
    BadgeSummary.BadgeCount DESC
LIMIT 100;