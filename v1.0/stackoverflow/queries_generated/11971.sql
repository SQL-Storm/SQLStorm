-- Performance benchmarking query to analyze the usage of posts and user interactions
SELECT 
    u.DisplayName AS UserDisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(p.Score) AS AverageScore,
    SUM(c.Id IS NOT NULL) AS TotalComments,
    SUM(v.Id IS NOT NULL) AS TotalVotes,
    MAX(p.CreationDate) AS LastPostDate,
    MIN(p.CreationDate) AS FirstPostDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
GROUP BY 
    u.DisplayName
ORDER BY 
    TotalPosts DESC
LIMIT 100;
