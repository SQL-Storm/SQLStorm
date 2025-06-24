
SELECT TOP 10
    p.Id AS PostId, 
    p.Title AS PostTitle, 
    u.DisplayName AS OwnerDisplayName, 
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 
ORDER BY 
    p.CreationDate DESC;
