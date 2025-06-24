
SELECT 
    p.Title, 
    p.CreationDate, 
    u.DisplayName AS Author, 
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
GROUP BY 
    p.Title, p.CreationDate, u.DisplayName, p.Id
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
