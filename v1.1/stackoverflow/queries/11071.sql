-- {"query": "11071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 873} 
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
        Posts.CreationDate > cast('2024-10-01' as date) - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(DISTINCT Posts.Id) AS PostCount, 
        COUNT(DISTINCT Comments.Id) AS CommentCount, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
        SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    LEFT JOIN 
        Comments ON Users.Id = Comments.UserId
    GROUP BY 
        Users.Id, 
        Users.DisplayName
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
    Users.Id, 
    Users.DisplayName, 
    UserActivity.PostCount, 
    UserActivity.CommentCount, 
    UserActivity.TotalScore, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    BadgeSummary.BadgeCount, 
    BadgeSummary.GoldBadgeCount, 
    BadgeSummary.SilverBadgeCount, 
    BadgeSummary.BronzeBadgeCount, 
    COUNT(DISTINCT RecentPosts.Id) AS RecentPostCount, 
    SUM(RecentPosts.Score) AS RecentScore, 
    SUM(RecentPosts.ViewCount) AS RecentViewCount, 
    COUNT(DISTINCT CASE WHEN RecentPosts.PostTypeId = 1 THEN RecentPosts.Id ELSE NULL END) AS RecentQuestionCount, 
    COUNT(DISTINCT CASE WHEN RecentPosts.PostTypeId = 2 THEN RecentPosts.Id ELSE NULL END) AS RecentAnswerCount
FROM 
    Users
LEFT JOIN 
    UserActivity ON Users.Id = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON Users.Id = BadgeSummary.UserId
LEFT JOIN 
    RecentPosts ON Users.Id = RecentPosts.OwnerUserId
GROUP BY 
    Users.Id, 
    Users.DisplayName, 
    UserActivity.PostCount, 
    UserActivity.CommentCount, 
    UserActivity.TotalScore, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    BadgeSummary.BadgeCount, 
    BadgeSummary.GoldBadgeCount, 
    BadgeSummary.SilverBadgeCount, 
    BadgeSummary.BronzeBadgeCount
HAVING 
    UserActivity.PostCount > 10 OR 
    BadgeSummary.BadgeCount > 5
ORDER BY 
    RecentScore DESC, 
    RecentViewCount DESC, 
    RecentPostCount DESC
LIMIT 10;