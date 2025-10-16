-- {"query": "11084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 804} 

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
        Posts.CreationDate > current_date - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        Users.Reputation, 
        COUNT(Posts.Id) AS PostCount, 
        SUM(Posts.Score) AS TotalScore, 
        COUNT(DISTINCT Posts.Id) AS UniquePostCount
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > current_date - INTERVAL '365' DAY
    GROUP BY 
        Users.Id, 
        Users.DisplayName, 
        Users.Reputation
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
TagCounts AS (
    SELECT 
        TagArray[n] AS Tag, 
        COUNT(*) AS Count
    FROM 
        PostTags, 
        generate_subscripts(TagArray, 1) AS n
    GROUP BY 
        TagArray[n]
),
TopTags AS (
    SELECT 
        Tag, 
        Count
    FROM 
        TagCounts
    ORDER BY 
        Count DESC
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
    UserActivity.DisplayName AS UserDisplayName, 
    UserActivity.Reputation, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.UniquePostCount,
    COALESCE(TopTags.Tag, 'No Tags') AS TopTag
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    TopTags ON array_position(PostTags.TagArray, TopTags.Tag) IS NOT NULL
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC
