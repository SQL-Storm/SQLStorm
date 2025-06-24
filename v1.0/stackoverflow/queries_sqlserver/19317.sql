
SELECT 
    p.Title, 
    p.CreationDate, 
    u.DisplayName AS Owner, 
    pt.Name AS PostType, 
    COUNT(c.Id) AS CommentCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
GROUP BY 
    p.Title, 
    p.CreationDate, 
    u.DisplayName, 
    pt.Name
ORDER BY 
    p.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
