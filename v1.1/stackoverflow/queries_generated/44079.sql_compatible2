SELECT
    p.Id AS PostId,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS AnswerCount,
    p.CommentCount AS CommentCount,
    p.FavoriteCount AS FavoriteCount,
    p.ClosedDate AS ClosedDate,
    p.CommunityOwnedDate AS CommunityOwnedDate,
    u.Id AS UserId,
    u.Reputation AS UserReputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    COALESCE(b.Name, '') AS BadgeName,
    COALESCE(b.Class, 0) AS BadgeClass,
    COALESCE(CASE WHEN b.TagBased IS NULL THEN 0 WHEN b.TagBased = TRUE THEN 1 ELSE 0 END, 0) AS BadgeIsTagBased,
    COALESCE(b.Date, p.CreationDate) AS BadgeDate,
    COALESCE(pt.Name, '') AS PostTypeName,
    COALESCE(cr.Name, '') AS CloseReasonName,
    COALESCE(v.Name, '') AS VoteTypeName,
    COALESCE(lt.Name, '') AS LinkTypeName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 3) AS DownVoteCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount
FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN CloseReasonTypes cr ON CAST(cr.Id AS VARCHAR) = CAST(p.ClosedDate AS VARCHAR)
    LEFT JOIN VoteTypes v ON v.Id = 2
    LEFT JOIN LinkTypes lt ON lt.Id = 3
WHERE
    p.CreationDate >= DATE '2010-01-01' AND p.CreationDate <= DATE '2020-12-31'
ORDER BY
    p.CreationDate DESC
FETCH FIRST 1000 ROWS ONLY;