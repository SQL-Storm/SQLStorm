-- {"query": "44079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 665}

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
    COALESCE(b.TagBased, 0) AS BadgeIsTagBased,
    COALESCE(b.Date, p.CreationDate) AS BadgeDate,
    COALESCE(pt.Name, '') AS PostTypeName,
    COALESCE(cr.Name, '') AS CloseReasonName,
    COALESCE(v.Name, '') AS VoteTypeName,
    COALESCE(lt.Name, '') AS LinkTypeName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount
FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN CloseReasonTypes cr ON CAST(p.ClosedDate AS varchar(10)) = cr.Id
    LEFT JOIN VoteTypes v ON v.Id = 2
    LEFT JOIN LinkTypes lt ON lt.Id = 3
WHERE
    p.CreationDate >= '2010-01-01' AND p.CreationDate <= '2020-12-31'
ORDER BY
    p.CreationDate DESC
LIMIT 1000;
