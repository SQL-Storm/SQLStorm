-- {"query": "6218.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 419}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.ViewCount > 100 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicates,
    MAX(ph.CreationDate) AS LastActivity,
    b.Name AS LatestBadge,
    b.Date AS BadgeDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecencyRank
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
    p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year')
    AND u.Reputation > 100
    AND (u.Id, b.Date) IN (
        SELECT 
            UserId, 
            MAX(Date) 
        FROM 
            Badges 
        GROUP BY 
            UserId
    )
GROUP BY 
    u.Id, u.DisplayName, b.Name, b.Date, p.LastActivityDate
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    TotalPosts DESC, 
    TotalVotes DESC;