-- {"query": "6153.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 344} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    MAX(u.LastAccessDate) AS LastAccess,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS TotalDuplicates,
    SUM(CASE WHEN b.TagBased THEN b.Class ELSE 0 END) AS TotalTagBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND pl.LinkTypeId = 3
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalQuestionScore DESC, 
    AvgViews DESC
LIMIT 100;
