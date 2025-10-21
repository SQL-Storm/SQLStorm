-- {"query": "40059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 159} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AverageScore,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 AND 
    u.Reputation > 1000 AND 
    p.CreationDate BETWEEN '2020-01-01' AND '2020-12-31';
