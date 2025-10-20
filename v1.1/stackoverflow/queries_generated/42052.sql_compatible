SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation, 
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
    AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '1' YEAR)
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    p.ViewCount,
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC
LIMIT 100;