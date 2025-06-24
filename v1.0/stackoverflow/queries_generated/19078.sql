SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS OwnerDisplayName, 
    p.Score, 
    p.CreationDate
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1  -- Only fetching questions
ORDER BY 
    p.CreationDate DESC
LIMIT 10;  -- Limit to the most recent 10 questions
