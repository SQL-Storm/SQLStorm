SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    AVG(v2.VoteTypeId) AS AverageVoteType,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkCount,
    COUNT(DISTINCT bh.Id) AS RevisionCount,
    STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(p.CreationDate) AS LastActivity,
    COUNT(DISTINCT b.Id) AS UserBadges
FROM
    Posts p
LEFT JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Votes v2 ON v2.PostId = p.Id AND v2.UserId = u.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    PostHistory bh ON bh.PostId = p.Id
LEFT JOIN
    Tags t ON POSITION(t.TagName IN COALESCE(p.Tags, '')) > 0
LEFT JOIN
    Badges b ON b.UserId = p.OwnerUserId
GROUP BY
    p.PostTypeId,
    pt.Name,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    p.Tags,
    p.CreationDate
ORDER BY
    u.Reputation DESC
LIMIT 100;