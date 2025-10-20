-- {"query": "44018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 41292, "output_tokens": 16301} 

SELECT
    p.Id AS PostId,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate AS PostLastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    u.Id AS UserId,
    u.Reputation AS UserReputation,
    u.DisplayName AS UserDisplayName,
    u.LastAccessDate AS UserLastAccessDate,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    v.Id AS VoteId,
    v.VoteTypeId AS VoteTypeId,
    v.CreationDate AS VoteCreationDate,
    v.BountyAmount AS VoteBountyAmount,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.CreationDate AS CommentCreationDate,
    pl.Id AS PostLinkId,
    pl.LinkTypeId AS PostLinkTypeId,
    pl.CreationDate AS PostLinkCreationDate,
    t.Id AS TagId,
    t.TagName AS TagName,
    t.Count AS TagCount,
    t.ExcerptPostId AS TagExcerptPostId,
    t.WikiPostId AS TagWikiPostId,
    t.IsModeratorOnly AS TagIsModeratorOnly,
    t.IsRequired AS TagIsRequired,
    ph.Id AS PostHistoryId,
    ph.PostHistoryTypeId AS PostHistoryTypeId,
    ph.CreationDate AS PostHistoryCreationDate,
    ph.Comment AS PostHistoryComment,
    ph.Text AS PostHistoryText
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
WHERE p.CreationDate > DATE_SUB(NOW(), INTERVAL 1 YEAR)
ORDER BY p.CreationDate DESC
LIMIT 1000;
