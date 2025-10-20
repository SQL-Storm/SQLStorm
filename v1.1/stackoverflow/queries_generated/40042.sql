-- {"query": "40042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 179} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(u.Reputation) AS MaxReputation,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestActivity
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 AND 
    p.LastActivityDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY);
