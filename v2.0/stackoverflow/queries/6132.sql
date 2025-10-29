SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount,0) ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(u.CreationDate) AS AccountCreationDate,
    b.Name AS TopBadge,
    b.Class AS BadgeClass
FROM 
    Users u
LEFT JOIN 
    (
      SELECT 
         UserId, 
         MAX(CASE WHEN Class = 1 THEN Name END) AS Name, 
         MAX(CASE WHEN Class = 1 THEN Class END) AS Class
     FROM 
         Badges
     GROUP BY 
         UserId
    ) b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= DATE_TRUNC('month', DATE '2024-10-01') - INTERVAL '6' MONTH
    AND EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.PostId = p.Id AND c.Score > 0
    )
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Name,
    b.Class
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalScore DESC
LIMIT 100;