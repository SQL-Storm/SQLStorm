SELECT 
    p.Id, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(ph.Id) AS EditCount, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    COUNT(DISTINCT v.UserId) AS UniqueVoters
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY 
    p.Id, p.Title, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    VoteCount DESC, 
    CommentCount DESC, 
    EditCount DESC
LIMIT 100;