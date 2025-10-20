SELECT 
    p.Id, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    AVG(b.Class) AS AvgBadgeClass, 
    COUNT(ph.Id) AS HistoryCount, 
    COUNT(pl.Id) AS LinkCount, 
    COUNT(DISTINCT t.TagName) AS TagCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE 
    p.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 year')
GROUP BY 
    p.Id, p.Title, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 AND COUNT(c.Id) > 5
ORDER BY 
    VoteCount DESC, CommentCount DESC
LIMIT 100;