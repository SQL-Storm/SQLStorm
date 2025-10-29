-- {"query": "6972.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 613} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id ELSE NULL END) AS TotalPositiveScorePosts,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoritesToQuestions,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommunityOwnedPosts,
    SUM(CASE WHEN p.LastEditDate > p.CreationDate THEN 1 ELSE 0 END) AS TotalEditedPosts,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    b.Name AS TopBadge,
    COALESCE(b.Class, 0) AS BadgeClass,
    l.Name AS TopLinkType
FROM 
    Users u
LEFT JOIN 
    (SELECT UserId, Name, Class, Id 
     FROM Badges 
     WHERE Date = (SELECT MAX(Date) FROM Badges WHERE UserId = u.Id)) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT UserId, Name 
     FROM LinkTypes 
     WHERE Id = (SELECT TOP 1 LinkTypeId 
                  FROM PostLinks 
                  WHERE PostId = (SELECT Id 
                                  FROM Posts 
                                  WHERE OwnerUserId = u.Id 
                                  ORDER BY LastEditDate DESC
                                  LIMIT 1))) l ON u.Id = l.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    SUM(p.Score) > 1000
ORDER BY 
    TotalPosts DESC, 
    HighestScore DESC;
