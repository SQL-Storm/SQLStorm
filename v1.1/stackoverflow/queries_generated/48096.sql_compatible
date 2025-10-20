SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS ActualCommentCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
    ) AS OutgoingLinkCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1
    ) AS IncomingLinkCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS UpVoteCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS DownVoteCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId AND b.Class = 1
    ) AS OwnerGoldBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId AND b.Class = 2
    ) AS OwnerSilverBadges,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId AND b.Class = 3
    ) AS OwnerBronzeBadges,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    pt.Name = 'Question'
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    AND p.Score > 10
    AND p.ViewCount > 1000
    AND p.AnswerCount > 5
ORDER BY
    p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
LIMIT 100;