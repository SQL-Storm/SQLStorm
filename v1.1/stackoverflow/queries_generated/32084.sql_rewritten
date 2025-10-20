-- {"query": "32084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 231} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    COALESCE(SUM(p.Score), 0) AS TotalPostScore, 
    COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
    COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPosts, 
    COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalComments,
    (COALESCE(COUNT(b.Id), 0) / NULLIF(COUNT(DISTINCT p.Id), 0)) AS BadgePerPostRatio
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 0
ORDER BY 
    TotalPostScore DESC, 
    TotalCommentScore DESC, 
    BadgePerPostRatio DESC
LIMIT 50;