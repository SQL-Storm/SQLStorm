-- {"query": "11029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 942} 

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
        Posts.CreationDate > current_date - INTERVAL '1 month'
),
UserActivity AS (
    SELECT 
        Users.Id, 
        Users.Reputation, 
        Users.CreationDate, 
        Users.DisplayName, 
        Users.LastAccessDate, 
        Users.WebsiteUrl, 
        Users.Location, 
        Users.Views, 
        Users.UpVotes, 
        Users.DownVotes, 
        Users.ProfileImageUrl, 
        Users.EmailHash, 
        Users.AccountId 
    FROM 
        Users 
    WHERE 
        Users.LastAccessDate > current_date - INTERVAL '3 months'
),
PostVotes AS (
    SELECT 
        Votes.PostId, 
        AVG(CASE WHEN VoteTypes.Name = 'UpMod' THEN 1 ELSE 0 END) AS AvgUpVotes, 
        AVG(CASE WHEN VoteTypes.Name = 'DownMod' THEN 1 ELSE 0 END) AS AvgDownVotes 
    FROM 
        Votes 
    JOIN 
        VoteTypes ON Votes.VoteTypeId = VoteTypes.Id 
    GROUP BY 
        Votes.PostId
),
PostTags AS (
    SELECT 
        Posts.Id, 
        string_to_array(substring(Posts.Tags, 2, length(Posts.Tags)-2), ''><'') AS TagArray 
    FROM 
        Posts
),
TagCounts AS (
    SELECT 
        TagArray[1] AS Tag, 
        COUNT(*) AS Count 
    FROM 
        PostTags 
    GROUP BY 
        TagArray[1]
)
SELECT 
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
    UserActivity.Reputation, 
    UserActivity.DisplayName, 
    UserActivity.LastAccessDate, 
    PostVotes.AvgUpVotes, 
    PostVotes.AvgDownVotes, 
    COUNT(DISTINCT TagCounts.Tag) AS UniqueTagCount 
FROM 
    RecentPosts 
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.Id 
LEFT JOIN 
    PostVotes ON RecentPosts.Id = PostVotes.PostId 
LEFT JOIN 
    TagCounts ON RecentPosts.Id = PostTags.Id 
GROUP BY 
    RecentPosts.Id, 
    UserActivity.Id, 
    PostVotes.PostId, 
    TagCounts.Id 
HAVING 
    COALESCE(PostVotes.AvgUpVotes, 0) > 0 
    AND COALESCE(PostVotes.AvgDownVotes, 0) < 0.5 
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC, 
    RecentPosts.ViewCount DESC, 
    UniqueTagCount DESC;
