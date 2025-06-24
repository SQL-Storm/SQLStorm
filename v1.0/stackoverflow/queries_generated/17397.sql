SELECT 
    p.Title, 
    p.CreationDate, 
    p.Score, 
    u.DisplayName AS OwnerDisplayName, 
    COUNT(c.Id) AS CommentCount 
FROM 
    Posts p 
JOIN 
    Users u ON p.OwnerUserId = u.Id 
LEFT JOIN 
    Comments c ON p.Id = c.PostId 
WHERE 
    p.PostTypeId = 1  -- Considering only Questions
GROUP BY 
    p.Id, u.DisplayName 
ORDER BY 
    p.Score DESC 
LIMIT 10;
