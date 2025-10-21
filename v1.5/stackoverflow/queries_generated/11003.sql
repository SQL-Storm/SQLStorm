-- {"query": "11003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 960} 

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
        Posts.CreationDate > current_date - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END) AS QuestionCount, 
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END) AS AnswerCount, 
        SUM(Posts.Score) AS TotalScore
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
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
),
PostTags AS (
    SELECT 
        Posts.Id, 
        string_to_array(substring(Posts.Tags, 2, length(Posts.Tags)-2), ''><'') AS TagArray
    FROM 
        Posts
    WHERE 
        Posts.PostTypeId = 1
),
TagFrequency AS (
    SELECT 
        TagArray[n] AS Tag, 
        COUNT(*) AS Frequency
    FROM 
        PostTags, 
        generate_subscripts(TagArray, 1) AS n
    GROUP BY 
        TagArray[n]
),
TopTags AS (
    SELECT 
        Tag, 
        Frequency
    FROM 
        TagFrequency
    ORDER BY 
        Frequency DESC
    LIMIT 10
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
    UserActivity.DisplayName, 
    UserActivity.PostCount, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    UserActivity.TotalScore, 
    BadgeSummary.BadgeCount, 
    BadgeSummary.GoldBadgeCount, 
    BadgeSummary.SilverBadgeCount, 
    BadgeSummary.BronzeBadgeCount, 
    TopTags.Tag, 
    TopTags.Frequency
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON UserActivity.UserId = BadgeSummary.UserId
LEFT JOIN 
    TopTags ON RecentPosts.Tags LIKE '%' || TopTags.Tag || '%'
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC;
