SELECT 
    p.Id, 
    p.Title, 
    u.DisplayName, 
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(ph.Id) AS HistoryCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT b.UserId) AS BadgeCount,
    COUNT(pl.Id) AS LinkCount
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
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR)
GROUP BY 
    p.Id, 
    p.Title, 
    u.Id,
    u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    VoteCount DESC, 
    CommentCount DESC, 
    HistoryCount DESC
LIMIT 100;