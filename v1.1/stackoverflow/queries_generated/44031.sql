-- {"query": "44031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 634}
Here's an elaborate SQL query for performance benchmarking:

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
    b.Id AS BadgeId, 
    b.Name AS BadgeName, 
    b.Date AS BadgeDate, 
    b.Class AS BadgeClass, 
    b.TagBased AS BadgeTagBased, 
    c.Id AS CommentId, 
    c.Score AS CommentScore, 
    c.CreationDate AS CommentCreationDate, 
    ph.Id AS PostHistoryId, 
    ph.PostHistoryTypeId, 
    ph.CreationDate AS PostHistoryCreationDate, 
    ph.Comment AS PostHistoryComment, 
    pl.Id AS PostLinkId, 
    pl.LinkTypeId, 
    pl.CreationDate AS PostLinkCreationDate, 
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
FROM 
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Votes v ON p.Id = v.PostId
WHERE 
    p.CreationDate >= '2022-01-01' AND p.CreationDate <= '2022-12-31'
ORDER BY 
    p.CreationDate DESC
LIMIT 
    1000;
