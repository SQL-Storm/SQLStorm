SELECT 
    p.Id, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    COUNT(c.Id) AS CommentCount, 
    AVG(LENGTH(ph.Text)) AS AvgEditLength
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8, 11, 24, 31, 33, 34, 35, 36, 50, 52, 53)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId = 1 AND p.CreationDate >= (DATE '2024-10-01') - INTERVAL '1' YEAR
GROUP BY 
    p.Id, p.Title, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    TotalVotes DESC, 
    AvgEditLength DESC
LIMIT 100;