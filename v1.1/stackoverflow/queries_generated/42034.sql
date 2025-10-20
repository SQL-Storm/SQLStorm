-- {"query": "42034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 354} 

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
    p.CreationDate >= CURRENT_DATE - INTERVAL '1 year' AND 
    u.Reputation > 1000
GROUP BY 
    p.Id, 
    u.Id
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
