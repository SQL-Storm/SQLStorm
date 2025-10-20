-- {"query": "40058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 206} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LatestActivity
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    Badges b ON u.Id = b.UserId
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 AND 
    u.Reputation > 1000 AND 
    b.Class = 1 AND 
    v.VoteTypeId = 2
GROUP BY 
    p.PostTypeId
ORDER BY 
    TotalPosts DESC;
