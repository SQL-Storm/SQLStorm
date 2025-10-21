-- {"query": "10051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 351} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Name AS LatestBadge,
    ph.Comment AS LastPostEditComment,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyGiven
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
AND 
    p.CreationDate >= DATEADD(year, -2, GETDATE())
GROUP BY 
    u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
