
SELECT 
    u.DisplayName AS UserDisplayName, 
    p.Title AS PostTitle, 
    p.CreationDate AS PostCreationDate, 
    COUNT(c.Id) AS CommentCount 
FROM 
    Users u 
JOIN 
    Posts p ON u.Id = p.OwnerUserId 
LEFT JOIN 
    Comments c ON p.Id = c.PostId 
WHERE 
    p.PostTypeId = 1 
GROUP BY 
    u.DisplayName, p.Title, p.CreationDate 
ORDER BY 
    CommentCount DESC 
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
