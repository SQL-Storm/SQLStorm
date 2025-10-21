SELECT 
    u.Id,
    MAX(u.DisplayName) AS DisplayName,
    MAX(u.Reputation) AS Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(p.ViewCount) AS TotalViews, 
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Users AS u
LEFT JOIN 
    Posts AS p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments AS c ON p.Id = c.PostId
LEFT JOIN 
    Badges AS b ON u.Id = b.UserId
WHERE
    u.Reputation > 1000
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC, TotalViews DESC, MAX(u.Reputation) DESC
LIMIT 10;