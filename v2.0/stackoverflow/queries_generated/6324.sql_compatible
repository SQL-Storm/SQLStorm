SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName
FROM 
    Users u
LEFT JOIN 
    (
      SELECT 
         UserId, 
         MAX(Date) AS LastBadgeDate,
         Class
      FROM 
         Badges
      GROUP BY 
         UserId, Class
    ) b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
         TagName, 
         COUNT(*) AS TagCount,
         ExcerptPostId
      FROM 
         Tags
      GROUP BY 
         TagName, ExcerptPostId
    ) t ON t.ExcerptPostId IN 
    (
      SELECT 
         p2.Id
      FROM 
         Posts p2
      WHERE 
         p2.PostTypeId = 1 AND p2.ClosedDate IS NULL
    )
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 1000
    AND p.Score > 0
    AND p.ViewCount > 100
    AND EXISTS 
    (
      SELECT 1 
      FROM Votes v 
      WHERE v.PostId = p.Id 
        AND v.VoteTypeId = 2
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Class, t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;