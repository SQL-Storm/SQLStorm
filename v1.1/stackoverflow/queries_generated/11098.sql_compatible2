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
        Posts.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '30' DAY
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
        Users.AboutMe, 
        Users.Views, 
        Users.UpVotes AS UpVotesRaw, 
        Users.DownVotes AS DownVotesRaw, 
        Users.ProfileImageUrl, 
        Users.AccountId,
        COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
        COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount
    FROM 
        Users
    LEFT JOIN 
        Votes ON Users.Id = Votes.UserId
    GROUP BY 
        Users.Id,
        Users.Reputation,
        Users.CreationDate,
        Users.DisplayName,
        Users.LastAccessDate,
        Users.WebsiteUrl,
        Users.Location,
        Users.AboutMe,
        Users.Views,
        Users.UpVotes,
        Users.DownVotes,
        Users.ProfileImageUrl,
        Users.AccountId
),
PostTags AS (
    SELECT 
        Posts.Id AS PostId, 
        -- remove surrounding angle brackets and split on '><'
        regexp_split_to_array(
            CASE 
                WHEN Posts.Tags IS NULL THEN NULL
                WHEN LEFT(Posts.Tags,1) = '<' AND RIGHT(Posts.Tags,1) = '>' THEN SUBSTRING(Posts.Tags FROM 2 FOR (LENGTH(Posts.Tags) - 2))
                ELSE Posts.Tags
            END,
            '><'
        ) AS TagArray
    FROM 
        Posts
),
PostTagsCount AS (
    SELECT 
        PostId, 
        COALESCE(array_length(TagArray, 1), 0) AS TagCount,
        TagArray
    FROM 
        PostTags
    GROUP BY 
        PostId, TagArray
),
PostVotes AS (
    SELECT 
        PostId, 
        COUNT(VoteTypeId) AS VoteCount
    FROM 
        Votes
    GROUP BY 
        PostId
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
    string_agg(array_to_string(PostTags.TagArray, ','), ', ') AS Tags, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense, 
    UserActivity.Reputation, 
    UserActivity.UpVotesCount, 
    UserActivity.DownVotesCount, 
    PostTagsCount.TagCount, 
    PostVotes.VoteCount
FROM 
    RecentPosts
LEFT JOIN 
    PostTags ON RecentPosts.Id = PostTags.PostId
LEFT JOIN 
    PostTagsCount ON RecentPosts.Id = PostTagsCount.PostId
LEFT JOIN 
    PostVotes ON RecentPosts.Id = PostVotes.PostId
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.Id
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
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense, 
    UserActivity.Reputation, 
    UserActivity.UpVotesCount, 
    UserActivity.DownVotesCount, 
    PostTagsCount.TagCount, 
    PostVotes.VoteCount
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC, 
    PostTagsCount.TagCount DESC, 
    PostVotes.VoteCount DESC, 
    UserActivity.Reputation DESC
LIMIT 100;