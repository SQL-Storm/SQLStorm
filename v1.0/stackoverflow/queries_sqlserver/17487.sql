
SELECT TOP 10 
    u.DisplayName, 
    p.Title, 
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
    p.CreationDate DESC;
