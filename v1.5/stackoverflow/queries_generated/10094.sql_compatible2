SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(u.CreationDate) AS AccountCreationDate,
    b.Name AS TopBadge,
    b.Class AS BadgeClass
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         Name, 
         Class, 
         ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY Date DESC) AS rn
     FROM 
         Badges
    ) b ON u.Id = b.UserId AND b.rn = 1
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '2 years')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Class
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalScore DESC
LIMIT 100;