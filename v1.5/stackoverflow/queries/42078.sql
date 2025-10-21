SELECT 
    p.Id,
    p.Title,
    u.DisplayName AS Author,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8, 24)
LEFT JOIN 
    Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
GROUP BY 
    p.Id,
    p.Title,
    u.DisplayName
ORDER BY 
    TotalVotes DESC, 
    CommentCount DESC, 
    EditCount DESC, 
    BadgeCount DESC, 
    LinkCount DESC
LIMIT 100;