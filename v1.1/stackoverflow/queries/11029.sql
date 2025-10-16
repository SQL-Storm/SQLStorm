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
        Posts.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 month'
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
        Users.AccountId 
    FROM 
        Users 
    WHERE 
        Users.LastAccessDate > CAST('2024-10-01' AS date) - INTERVAL '3 months'
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
        regexp_split_to_array(trim(BOTH '<>' FROM Posts.Tags), '><') AS TagArray 
    FROM 
        Posts
),
TagCounts AS (
    SELECT 
        pt.Id AS PostId,
        ta AS Tag,
        COUNT(*) AS Count 
    FROM 
        PostTags pt,
        unnest(pt.TagArray) AS ta
    GROUP BY 
        pt.Id, ta
)
SELECT 
    rp.Id, 
    rp.PostTypeId, 
    rp.AcceptedAnswerId, 
    rp.ParentId, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.Body, 
    rp.OwnerUserId, 
    rp.OwnerDisplayName, 
    rp.LastEditorUserId, 
    rp.LastEditorDisplayName, 
    rp.LastEditDate, 
    rp.LastActivityDate, 
    rp.Title, 
    rp.Tags, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.FavoriteCount, 
    rp.ClosedDate, 
    rp.CommunityOwnedDate, 
    rp.ContentLicense, 
    ua.Reputation, 
    ua.DisplayName AS UserDisplayName, 
    ua.LastAccessDate, 
    pv.AvgUpVotes, 
    pv.AvgDownVotes, 
    COUNT(DISTINCT tc.Tag) AS UniqueTagCount 
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.Id 
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId 
LEFT JOIN 
    TagCounts tc ON rp.Id = tc.PostId 
GROUP BY 
    rp.Id, 
    rp.PostTypeId, 
    rp.AcceptedAnswerId, 
    rp.ParentId, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.Body, 
    rp.OwnerUserId, 
    rp.OwnerDisplayName, 
    rp.LastEditorUserId, 
    rp.LastEditorDisplayName, 
    rp.LastEditDate, 
    rp.LastActivityDate, 
    rp.Title, 
    rp.Tags, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.FavoriteCount, 
    rp.ClosedDate, 
    rp.CommunityOwnedDate, 
    rp.ContentLicense, 
    ua.Id, 
    ua.Reputation, 
    ua.DisplayName, 
    ua.LastAccessDate, 
    pv.PostId, 
    pv.AvgUpVotes, 
    pv.AvgDownVotes
HAVING 
    COALESCE(pv.AvgUpVotes, 0) > 0 
    AND COALESCE(pv.AvgDownVotes, 0) < 0.5 
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    UniqueTagCount DESC;