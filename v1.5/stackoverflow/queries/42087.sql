SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    u.DisplayName AS OwnerName, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT c.Id) AS TotalComments, 
    COUNT(DISTINCT ph.Id) AS TotalEdits, 
    COUNT(DISTINCT b.Id) AS TotalBadges, 
    COUNT(DISTINCT pl.Id) AS TotalLinks
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
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(DISTINCT c.Id) > 5
ORDER BY 
    p.Score DESC, 
    TotalVotes DESC, 
    TotalComments DESC, 
    TotalEdits DESC, 
    TotalBadges DESC, 
    TotalLinks DESC
LIMIT 100;