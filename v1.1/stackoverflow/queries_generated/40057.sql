-- {"query": "40057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 268} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    AVG(DATEDIFF(day, u.CreationDate, CURRENT_TIMESTAMP)) AS AvgUserAge
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId IN (1, 2) AND 
    u.Id IS NOT NULL AND 
    b.Id IS NOT NULL AND 
    v.PostId IS NOT NULL AND 
    c.PostId IS NOT NULL;
