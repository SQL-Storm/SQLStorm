-- Performance benchmarking query for the StackOverflow schema

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    SUM(v.CreationDate IS NOT NULL) AS TotalVotes,
    AVG(u.Reputation) AS AverageReputation,
    MAX(u.CreationDate) AS MostRecentAccountCreation
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId 
LEFT JOIN 
    Votes v ON p.Id = v.PostId 
GROUP BY 
    u.Id, u.DisplayName
ORDER BY 
    TotalPosts DESC
LIMIT 100;
