-- {"query": "44090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 206460, "output_tokens": 70216} 

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
    u.DisplayName,
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
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.CreationDate AS CommentCreationDate,
    c.UserId AS CommentUserId,
    c.UserDisplayName AS CommentUserDisplayName,
    pl.Id AS PostLinkId,
    pl.CreationDate AS PostLinkCreationDate,
    pl.RelatedPostId,
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
    v.UserId AS VoteUserId,
    v.BountyAmount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.CreationDate >= '2022-01-01' AND p.CreationDate < '2023-01-01'
ORDER BY p.Id, b.Date, c.CreationDate, pl.CreationDate, v.CreationDate;
