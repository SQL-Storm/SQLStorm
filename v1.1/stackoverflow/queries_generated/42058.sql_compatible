SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    AVG(LENGTH(ph.Text)) AS AvgEditLength, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypes
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1 
AND 
    p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    p.Title,
    u.DisplayName
HAVING 
    COUNT(v.Id) > 0 
AND 
    COUNT(DISTINCT ph.UserId) > 0
ORDER BY 
    TotalVotes DESC, 
    UniqueEditors DESC, 
    AvgEditLength DESC
LIMIT 100;