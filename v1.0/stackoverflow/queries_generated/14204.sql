-- Performance Benchmarking Query
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    MAX(h.CreationDate) AS LastEditDate,
    MAX(h.PostHistoryTypeId) AS LastActionType
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory h ON p.Id = h.PostId
WHERE 
    p.CreationDate >= '2023-01-01' -- Filter to posts created in the current year
GROUP BY 
    p.Id, u.DisplayName
ORDER BY 
    p.Score DESC, p.ViewCount DESC
LIMIT 100; -- Limiting to top 100 posts for benchmarking
