SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS OwnerName, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount 
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1  -- Get only questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
