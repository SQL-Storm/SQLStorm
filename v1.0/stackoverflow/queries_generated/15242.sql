SELECT 
    p.Title, 
    p.Body, 
    u.DisplayName AS Author, 
    p.CreationDate, 
    p.Score 
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1 -- Selecting Questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
