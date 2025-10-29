SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class AS BadgeClass,
    t.TagName
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         MIN(Date) AS FirstBadgeDate, 
         MAX(Date) AS LastBadgeDate, 
         Class, 
         TagBased
     FROM 
         Badges
     GROUP BY 
         UserId, Class, TagBased) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         Id, 
         Name, 
         MIN(Date) AS FirstEarnedDate
     FROM 
         Badges
     GROUP BY 
         Id, Name) b2 ON b.UserId = b2.Id
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
GROUP BY 
    u.DisplayName, u.Reputation, b.Class, t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;