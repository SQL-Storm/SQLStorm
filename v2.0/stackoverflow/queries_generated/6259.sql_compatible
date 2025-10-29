SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Count AS TotalBadges,
    AVG(v.BountyAmount) AS AvgBounty
FROM 
    Users u
LEFT JOIN 
    (SELECT UserId, COUNT(Id) AS Count 
     FROM Badges 
     GROUP BY UserId) b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT PostId, SUM(BountyAmount) AS BountyAmount 
     FROM Votes 
     WHERE VoteTypeId = 8 
     GROUP BY PostId) v ON p.Id = v.PostId
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate IS NOT NULL
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
GROUP BY 
    u.DisplayName, u.Reputation, b.Count
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;