SELECT 
    u.DisplayName AS UserName, 
    p.Title AS PostTitle, 
    p.CreationDate AS PostCreatedDate, 
    COUNT(c.Id) AS CommentCount
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1 -- Filtering for Questions
GROUP BY 
    u.DisplayName, p.Title, p.CreationDate
ORDER BY 
    PostCreatedDate DESC
LIMIT 10;
