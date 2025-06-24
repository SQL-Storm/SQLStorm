-- Performance benchmarking query for the Stack Overflow schema

-- Measure the number of posts, comments, and votes alongside users' reputation
SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    AVG(u.Reputation) AS AverageReputation,
    SUM(u.UpVotes) AS TotalUpVotes,
    SUM(u.DownVotes) AS TotalDownVotes
FROM 
    Posts p
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.CreationDate >= '2023-01-01'  -- Consider only posts created in 2023
GROUP BY 
    u.Reputation
ORDER BY 
    TotalPosts DESC;
