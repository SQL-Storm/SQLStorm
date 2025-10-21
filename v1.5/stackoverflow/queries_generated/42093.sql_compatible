SELECT 
    p.Id, 
    p.Title, 
    COUNT(v.Id) AS VoteCount,
    u.DisplayName,
    u.Reputation,
    COUNT(c.Id) AS CommentCount,
    COUNT(ph.Id) AS PostHistoryCount,
    COUNT(pl.Id) AS PostLinkCount,
    COUNT(b.Id) AS BadgeCount,
    COUNT(t.Id) AS TagCount
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
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE 
    p.CreationDate >= DATE '2020-01-01'
    AND p.PostTypeId = 1
GROUP BY 
    p.Id, p.Title, u.DisplayName, u.Reputation
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    COUNT(v.Id) DESC, 
    COUNT(c.Id) DESC
LIMIT 100;