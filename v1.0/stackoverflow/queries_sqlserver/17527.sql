
SELECT 
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS Author,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1  
GROUP BY 
    p.Id, p.Title, u.DisplayName, p.CreationDate, p.Score, p.ViewCount
ORDER BY 
    p.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
