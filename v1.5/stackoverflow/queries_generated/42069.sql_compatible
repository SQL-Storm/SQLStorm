SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    u.DisplayName, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(ph.Id) AS HistoryCount, 
    COUNT(b.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount
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
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    u.DisplayName, 
    u.Id
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;