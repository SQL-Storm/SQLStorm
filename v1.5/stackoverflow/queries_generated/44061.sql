-- {"query": "44061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 139934, "output_tokens": 48575} 

SELECT 
    p.Id AS PostId, 
    p.Title, 
    p.Body, 
    p.CreationDate, 
    p.LastEditDate, 
    p.LastActivityDate, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ViewCount, 
    p.Score, 
    p.OwnerUserId, 
    p.LastEditorUserId, 
    u.Reputation, 
    u.DisplayName, 
    u.WebsiteUrl, 
    u.Location, 
    u.AboutMe, 
    u.Views, 
    u.UpVotes, 
    u.DownVotes, 
    u.ProfileImageUrl, 
    u.EmailHash, 
    u.AccountId, 
    b.Id AS BadgeId, 
    b.Name AS BadgeName, 
    b.Date AS BadgeDate, 
    b.Class AS BadgeClass, 
    b.TagBased AS BadgeTagBased, 
    c.Id AS CommentId, 
    c.Score AS CommentScore, 
    c.Text AS CommentText, 
    c.CreationDate AS CommentCreationDate, 
    c.UserDisplayName AS CommentUserDisplayName, 
    c.UserId AS CommentUserId, 
    pt.Name AS PostTypeName, 
    lt.Name AS LinkTypeName, 
    vt.Name AS VoteTypeName, 
    crt.Name AS CloseReasonTypeName, 
    ph.Id AS PostHistoryId, 
    ph.PostHistoryTypeId, 
    ph.RevisionGUID, 
    ph.CreationDate AS PostHistoryCreationDate, 
    ph.UserId AS PostHistoryUserId, 
    ph.UserDisplayName AS PostHistoryUserDisplayName, 
    ph.Comment AS PostHistoryComment, 
    ph.Text AS PostHistoryText, 
    pl.Id AS PostLinkId, 
    pl.CreationDate AS PostLinkCreationDate, 
    pl.RelatedPostId, 
    t.Id AS TagId, 
    t.TagName, 
    t.Count AS TagCount, 
    t.ExcerptPostId, 
    t.WikiPostId, 
    t.IsModeratorOnly, 
    t.IsRequired, 
    v.Id AS VoteId, 
    v.VoteTypeId, 
    v.CreationDate AS VoteCreationDate, 
    v.BountyAmount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN CloseReasonTypes crt ON ph.Comment = CAST(crt.Id AS VARCHAR(400))
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
LEFT JOIN Tags t ON p.Tags LIKE '%<' + t.TagName + '>%'
LEFT JOIN Votes v ON v.PostId = p.Id
```

This query retrieves a comprehensive set of data from the StackOverflow database schema, including information about posts, users, badges, comments, post history, post links, tags, and votes. The query uses multiple left joins to combine data from various tables and provides a detailed view of the data. This query can be used for performance benchmarking and data analysis purposes.