SELECT 
    p.Id AS PostId,
    p.Title,
    p.Body,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Filtering for Questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
