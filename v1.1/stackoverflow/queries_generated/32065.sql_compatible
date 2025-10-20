SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
    AVG(p.Score) AS AverageScore,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditHistoryCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
WHERE 
    u.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    AND u.Reputation > 1000
    AND (p.PostTypeId IN (1, 2) OR p.Id IS NULL)
GROUP BY 
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(p.Id) > 10
ORDER BY 
    TotalUpvotes DESC,
    TotalDownvotes ASC,
    AverageScore DESC;