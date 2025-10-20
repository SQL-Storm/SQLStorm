-- {"query": "44023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 52762, "output_tokens": 20725} 

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
    b.TagBased AS BadgeIsTagBased,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.CreationDate AS CommentCreationDate,
    v.Id AS VoteId,
    v.VoteTypeId,
    v.CreationDate AS VoteCreationDate,
    v.BountyAmount,
    l.Id AS LinkId,
    l.LinkTypeId,
    l.CreationDate AS LinkCreationDate,
    t.Id AS TagId,
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired,
    ph.Id AS PostHistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS PostHistoryCreationDate,
    ph.Comment,
    ph.Text
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks l ON p.Id = l.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
ORDER BY p.Id, b.Id, c.Id, v.Id, l.Id, t.Id, ph.Id;
