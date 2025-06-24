SELECT 
    p.Title,
    p.CreationDate,
    u.DisplayName as Author,
    p.ViewCount,
    p.Score
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Selecting only Questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
