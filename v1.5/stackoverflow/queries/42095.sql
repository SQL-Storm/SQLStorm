SELECT
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName AS Owner,
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(ph.Id) AS PostHistoryCount,
    COUNT(pl.Id) AS PostLinkCount,
    COUNT(b.Id) AS BadgeCount
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN
    Badges b ON u.Id = b.UserId
WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName
ORDER BY
    p.Score DESC, VoteCount DESC, CommentCount DESC, PostHistoryCount DESC, PostLinkCount DESC, BadgeCount DESC
LIMIT 100;