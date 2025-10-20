-- {"query": "40031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 144} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    SUM(p.Score) AS TotalScore,
    MAX(u.Reputation) AS MaxReputation,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestActivity,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId;
