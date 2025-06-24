SELECT 
    u.DisplayName AS UserName,
    p.Title AS PostTitle,
    p.CreationDate AS PostDate,
    COUNT(c.Id) AS CommentCount
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1 -- Only considering Questions
GROUP BY 
    u.DisplayName, p.Title, p.CreationDate
ORDER BY 
    PostDate DESC
LIMIT 10;
