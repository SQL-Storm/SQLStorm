
SELECT 
    p.Title,
    p.Body,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1  
GROUP BY 
    p.Title, 
    p.Body, 
    u.DisplayName, 
    p.CreationDate, 
    p.ViewCount
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
