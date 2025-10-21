-- {"query": "44058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 740}

SELECT 
    p.Id, 
    p.PostTypeId, 
    p.ParentId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.CreationDate AS CommentCreationDate,
    c.UserId AS CommentUserId,
    c.ContentLicense AS CommentContentLicense,
    ph.Id AS PostHistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS PostHistoryCreationDate,
    ph.UserId AS PostHistoryUserId,
    ph.Comment AS PostHistoryComment,
    ph.Text AS PostHistoryText,
    ph.ContentLicense AS PostHistoryContentLicense,
    pl.Id AS PostLinkId,
    pl.CreationDate AS PostLinkCreationDate,
    pl.LinkTypeId,
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
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
LEFT JOIN Votes v ON p.Id = v.PostId
ORDER BY p.Id, b.Date, c.CreationDate, ph.CreationDate, pl.CreationDate, t.TagName, v.CreationDate
```

This SQL query performs a comprehensive performance benchmark on the StackOverflow database schema by joining multiple tables and aggregating various data points. The query retrieves information about posts, users, badges, comments, post history, post links, tags, and votes. The result set provides a rich dataset for analyzing the performance and characteristics of the database.
