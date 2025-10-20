-- {"query": "42009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 341} 

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
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY 
    p.Id, u.Id
HAVING 
    COUNT(v.Id) > 10
    AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    p.Score DESC, 
    COUNT(v.Id) DESC, 
    COUNT(DISTINCT ph.UserId) DESC
LIMIT 100;
