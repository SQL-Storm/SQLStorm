-- {"query": "6259.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 413} 

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
    AND p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;
