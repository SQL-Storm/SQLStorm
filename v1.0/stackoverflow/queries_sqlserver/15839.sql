
SELECT TOP 10
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS Author,
    p.Score,
    p.ViewCount,
    p.CreationDate
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 
ORDER BY 
    p.CreationDate DESC;
