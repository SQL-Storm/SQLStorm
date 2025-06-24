SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS Owner, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount 
FROM 
    Posts p 
JOIN 
    Users u ON p.OwnerUserId = u.Id 
WHERE 
    p.PostTypeId = 1 
ORDER BY 
    p.Score DESC 
LIMIT 10;
