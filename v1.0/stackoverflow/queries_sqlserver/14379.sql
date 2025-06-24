
SELECT 
    p.Id AS PostId, 
    p.Title, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    u.Reputation AS OwnerReputation, 
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
    p.CreationDate >= '2023-01-01'  
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.Reputation
ORDER BY 
    p.CreationDate DESC, 
    p.Score DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
