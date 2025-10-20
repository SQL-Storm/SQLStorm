-- {"query": "11048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 961} 

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
        Posts.CreationDate > current_date - interval '30 days'
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
        Posts.CreationDate > current_date - interval '365 days'
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgeCount
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
        Posts.Tags IS NOT NULL
),
TagUsage AS (
    SELECT 
        TagArray[i] AS TagName, 
        count(*) AS UsageCount
    FROM 
        PostTags, 
        generate_subscripts(PostTags.TagArray, 1) AS i
    GROUP BY 
        TagName
    HAVING 
        count(*) > 10
),
PostCommentActivity AS (
    SELECT 
        Comments.PostId, 
        COUNT(Comments.Id) AS CommentCount
    FROM 
        Comments
    GROUP BY 
        Comments.PostId
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
    UserActivity.DisplayName AS UserDisplayName, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    BadgeSummary.BadgeCount, 
    PostCommentActivity.CommentCount, 
    TagUsage.TagName, 
    TagUsage.UsageCount
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
LEFT JOIN 
    PostCommentActivity ON RecentPosts.Id = PostCommentActivity.PostId
LEFT JOIN 
    TagUsage ON RecentPosts.Tags LIKE '%' || TagUsage.TagName || '%'
ORDER BY 
    RecentPosts.CreationDate DESC, 
    UserActivity.TotalScore DESC, 
    BadgeSummary.BadgeCount DESC, 
    PostCommentActivity.CommentCount DESC, 
    TagUsage.UsageCount DESC;
