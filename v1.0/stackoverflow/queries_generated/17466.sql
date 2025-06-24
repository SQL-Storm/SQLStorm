SELECT 
    p.Title, 
    p.CreationDate, 
    u.DisplayName AS OwnerDisplayName, 
    p.Score, 
    p.ViewCount 
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1  -- Filter to only get Questions
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC
LIMIT 10;
