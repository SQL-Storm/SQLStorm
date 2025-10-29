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
    b2.Name AS TopBadge,
    b2.Class AS BadgeClass
FROM 
    Users u
LEFT JOIN 
    (SELECT UserId, MAX(Id) AS MaxBadgeId
     FROM Badges 
     GROUP BY UserId) bmax ON u.Id = bmax.UserId
LEFT JOIN 
    Badges b2 ON bmax.UserId = b2.UserId AND bmax.MaxBadgeId = b2.Id
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b2.Name, b2.Class
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, TotalViews DESC
LIMIT 100;