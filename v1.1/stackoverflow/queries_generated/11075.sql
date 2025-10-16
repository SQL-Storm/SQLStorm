-- {"query": "11075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 738} 

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
        COALESCE(SUM(Posts.Score), 0) AS TotalScore, 
        COALESCE(COUNT(DISTINCT Posts.Id), 0) AS TotalPosts
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeEarnings AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS TotalBadges
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
    PostTags.TagArray AS Tags,
    RecentPosts.AnswerCount,
    RecentPosts.CommentCount,
    RecentPosts.FavoriteCount,
    RecentPosts.ClosedDate,
    RecentPosts.CommunityOwnedDate,
    RecentPosts.ContentLicense,
    UserActivity.DisplayName AS OwnerDisplayName,
    UserActivity.TotalScore,
    UserActivity.TotalPosts,
    BadgeEarnings.TotalBadges,
    COALESCE(SUM(Votes.Score) OVER (PARTITION BY RecentPosts.Id), 0) AS TotalVotes
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeEarnings ON RecentPosts.OwnerUserId = BadgeEarnings.UserId
LEFT JOIN 
    Votes ON RecentPosts.Id = Votes.PostId
LEFT JOIN 
    PostTags ON RecentPosts.Id = PostTags.Id
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC, 
    UserActivity.TotalScore DESC, 
    BadgeEarnings.TotalBadges DESC
