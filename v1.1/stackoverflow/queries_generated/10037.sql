-- {"query": "10037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 423} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.CommunityOwnedDate IS NOT NULL) AS TotalCommunityOwnedPosts,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.Score) AS LowestScoredPost,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    b.Name AS TopBadge,
    b.Date AS BadgeDate,
    ph.Comment AS LastEditComment
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 11
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= DATEADD(year, -5, CURRENT_TIMESTAMP)
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
GROUP BY 
    u.Id, 
    b.Id, 
    ph.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC
LIMIT 100;
