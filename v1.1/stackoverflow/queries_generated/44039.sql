-- {"query": "44039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 731}
SELECT 
    p.Id AS PostId, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    u.Id AS UserId, 
    u.Reputation, 
    u.CreationDate AS UserCreationDate, 
    u.LastAccessDate, 
    u.Views AS UserViews, 
    u.UpVotes AS UserUpVotes, 
    u.DownVotes AS UserDownVotes, 
    b.Id AS BadgeId, 
    b.Name AS BadgeName, 
    b.Date AS BadgeDate, 
    b.Class AS BadgeClass, 
    b.TagBased AS BadgeTagBased, 
    pt.Name AS PostTypeName, 
    l.Name AS LinkTypeName, 
    cr.Name AS CloseReasonName, 
    v.Name AS VoteTypeName, 
    ph.PostHistoryTypeId, 
    ph.CreationDate AS PostHistoryCreationDate, 
    ph.UserId AS PostHistoryUserId, 
    ph.UserDisplayName AS PostHistoryUserDisplayName, 
    ph.Comment AS PostHistoryComment, 
    ph.Text AS PostHistoryText, 
    pl.CreationDate AS PostLinkCreationDate, 
    pl.LinkTypeId AS PostLinkTypeId, 
    t.TagName, 
    t.Count AS TagCount, 
    t.ExcerptPostId, 
    t.WikiPostId, 
    t.IsModeratorOnly, 
    t.IsRequired, 
    v2.VoteTypeId AS VoteId, 
    v2.CreationDate AS VoteCreationDate, 
    v2.BountyAmount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN LinkTypes l ON pl.LinkTypeId = l.Id
LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INT) = cr.Id
LEFT JOIN VoteTypes v ON v2.VoteTypeId = v.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
LEFT JOIN Votes v2 ON p.Id = v2.PostId
WHERE p.Id IN (
    SELECT Id 
    FROM Posts
    WHERE PostTypeId = 1 
    ORDER BY ViewCount DESC
    LIMIT 100
)
ORDER BY p.ViewCount DESC;
