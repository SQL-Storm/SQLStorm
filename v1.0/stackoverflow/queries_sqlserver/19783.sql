
SELECT 
    p.Id AS PostId,
    p.Title,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate
FROM 
    Posts p
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1  
GROUP BY 
    p.Id, p.Title, u.DisplayName, p.CreationDate
ORDER BY 
    p.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
