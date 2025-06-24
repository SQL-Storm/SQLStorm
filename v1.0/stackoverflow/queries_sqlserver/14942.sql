
SELECT 
    pt.Name AS PostType,
    AVG(DATEDIFF(MINUTE, p.CreationDate, p.LastActivityDate)) AS AvgResponseTimeMin,
    AVG(u.Reputation) AS AvgUserReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
GROUP BY 
    pt.Name, p.CreationDate, p.LastActivityDate, u.Reputation
ORDER BY 
    AvgResponseTimeMin DESC;
