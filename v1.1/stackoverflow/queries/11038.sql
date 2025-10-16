WITH RecentPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        AcceptedAnswerId, 
        ParentId, 
        CreationDate, 
        Score, 
        ViewCount, 
        Body, 
        OwnerUserId, 
        OwnerDisplayName, 
        LastEditorUserId, 
        LastEditorDisplayName, 
        LastEditDate, 
        LastActivityDate, 
        Title, 
        Tags, 
        AnswerCount, 
        CommentCount, 
        FavoriteCount, 
        ClosedDate, 
        CommunityOwnedDate, 
        ContentLicense
    FROM 
        Posts
    WHERE 
        CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT 
        Id, 
        Reputation, 
        CreationDate, 
        DisplayName, 
        LastAccessDate, 
        WebsiteUrl, 
        Location, 
        Views, 
        UpVotes, 
        DownVotes, 
        ProfileImageUrl, 
        AccountId
    FROM 
        Users
    WHERE 
        LastAccessDate > CAST('2024-10-01' AS DATE) - INTERVAL '90' DAY
),
PostVotes AS (
    SELECT 
        PostId, 
        COUNT(Id) AS VoteCount, 
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, 
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Votes
    GROUP BY 
        PostId
),
PostTags AS (
    SELECT 
        p.Id, 
        t.TagName
    FROM 
        Posts p
    LEFT JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
)
SELECT 
    rp.Id AS PostId, 
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
    STRING_AGG(pt.TagName, ', ') AS Tags, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.FavoriteCount, 
    rp.ClosedDate, 
    rp.CommunityOwnedDate, 
    rp.ContentLicense, 
    COALESCE(pv.VoteCount, 0) AS VoteCount, 
    COALESCE(pv.UpVoteCount, 0) AS UpVoteCount, 
    COALESCE(pv.DownVoteCount, 0) AS DownVoteCount, 
    ua.Reputation, 
    ua.DisplayName, 
    ua.LastAccessDate
FROM 
    RecentPosts rp
LEFT JOIN 
    PostVotes pv ON rp.Id = pv.PostId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.Id
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
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.FavoriteCount, 
    rp.ClosedDate, 
    rp.CommunityOwnedDate, 
    rp.ContentLicense, 
    pv.VoteCount, 
    pv.UpVoteCount, 
    pv.DownVoteCount, 
    ua.Reputation, 
    ua.DisplayName, 
    ua.LastAccessDate
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC
LIMIT 100;