SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId ELSE NULL END) AS TotalDuplicates,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.AnswerCount) AS TotalAnswersCount,
    AVG(p.Score) AS AvgScore,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.AnswerCount) AS AvgAnswersCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
GROUP BY 
    u.DisplayName, u.Reputation, u.Location, u.AboutMe
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalViews DESC, 
    TotalScore DESC
LIMIT 10;