SELECT 
    u.Id,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.ViewCount > 100 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicates,
    MAX(ph.CreationDate) AS LastActivity,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND (p.CreationDate IS NULL OR p.CreationDate >= (DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '1 year'))
    AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    b.Id,
    b.Name,
    b.Date
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    TotalPosts DESC, 
    LatestBadge DESC;