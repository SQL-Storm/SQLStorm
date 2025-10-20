SELECT 
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctEditTypes,
    COUNT(DISTINCT ph.CreationDate) AS EditDatesCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditorsCount,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypesCount,
    COUNT(DISTINCT ph.CreationDate) AS UniqueEditDatesCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= CAST(DATE '2024-10-01' AS DATE) - INTERVAL '1' YEAR
GROUP BY 
    p.Id,
    p.Title,
    p.Score,
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(v.Id) > 10
    AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    p.Score DESC, 
    TotalVotes DESC, 
    UniqueEditors DESC
LIMIT 100;