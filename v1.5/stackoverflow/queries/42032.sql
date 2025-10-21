-- {"query": "42032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 365} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalPositiveScore,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    MAX(p.CreationDate) AS LatestActivityDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.CreationDate >= '2020-01-01' 
    AND p.CreationDate >= '2020-01-01'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 10
ORDER BY 
    TotalPositiveScore DESC, 
    TotalPosts DESC 
LIMIT 100;