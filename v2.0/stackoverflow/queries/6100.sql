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
    b.Class AS BadgeClass,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT UserId, MAX(Id) AS MaxBadgeId 
     FROM Badges 
     GROUP BY UserId) bb ON b.UserId = bb.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT Id, MAX(Date) AS MaxDate 
     FROM Badges 
     GROUP BY Id) bb2 ON b.UserId = bb2.Id AND b.Date = bb2.MaxDate
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Class, b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalViews DESC, 
    TotalPositiveScorePosts DESC;