SELECT 
    p.Title, 
    p.Score, 
    u.DisplayName AS OwnerDisplayName, 
    p.CreationDate, 
    p.ViewCount 
FROM 
    Posts p 
JOIN 
    Users u ON p.OwnerUserId = u.Id 
WHERE 
    p.PostTypeId = 1 
ORDER BY 
    p.CreationDate DESC 
LIMIT 10;