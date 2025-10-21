-- {"query": "42022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 348} 

SELECT 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(ph.Id) AS HistoryCount,
    COUNT(pl.Id) AS LinkCount,
    COUNT(DISTINCT t.TagName) AS TagCount,
    MAX(b.Date) AS LatestBadgeDate,
    MAX(ph.CreationDate) AS LatestHistoryDate,
    MAX(pl.CreationDate) AS LatestLinkDate
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
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY 
    p.Id, u.DisplayName
HAVING 
    COUNT(v.Id) > 10
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, p.ViewCount DESC
LIMIT 100;
