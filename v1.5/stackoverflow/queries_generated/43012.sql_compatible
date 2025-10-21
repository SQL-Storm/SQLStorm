SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(p.Score) AS TotalScore,
    MAX(p.ViewCount) AS MaxViewCount,
    b.Name AS BadgeName,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN 
    (SELECT UserId, Name, MAX(Date) AS LatestBadgeDate
     FROM Badges
     WHERE Class = 1
     GROUP BY UserId, Name) b ON u.Id = b.UserId
WHERE 
    u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
GROUP BY 
    u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalScore DESC, MaxViewCount DESC
LIMIT 100;