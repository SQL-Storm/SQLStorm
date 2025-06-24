SELECT 
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    v.CreationDate AS VoteDate,
    COUNT(c.Id) AS CommentCount
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1 -- only questions
GROUP BY 
    p.Id, u.DisplayName, v.CreationDate
ORDER BY 
    p.CreationDate DESC
LIMIT 10;
