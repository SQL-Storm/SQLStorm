SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation, 
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS HistoryEventCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditorsCount,
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
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId = 1 AND 
    p.CreationDate >= DATE '2024-10-01' - INTERVAL '1' YEAR AND 
    u.Reputation > 1000
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    p.ViewCount,
    u.DisplayName,
    u.Reputation
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    VoteCount DESC, 
    CommentCount DESC, 
    HistoryEventCount DESC, 
    UniqueEditorsCount DESC, 
    BadgeCount DESC, 
    LinkCount DESC
LIMIT 100;