SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 1 THEN p.Id END) AS TotalAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicatePosts,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.Score) AS LowestScoredPost,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.FavoriteCount) AS TotalFavorites,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TagList,
    MAX(u.LastAccessDate) AS LastAccessDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS MostRecentActivity,
    COALESCE(SUM(b.Class), 0) AS TotalBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes pv ON p.Id = pv.PostId AND pv.VoteTypeId = 1
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
        Id, 
        STRING_AGG(CAST(TagName AS varchar), ', ' ORDER BY TagName) AS TagName
      FROM Tags
      GROUP BY Id
    ) t ON p.Id = t.Id
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2' YEAR)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    TotalViews DESC, 
    TotalPosts DESC;