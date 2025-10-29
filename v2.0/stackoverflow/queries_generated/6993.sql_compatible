SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    MAX(ph.CreationDate) AS LatestPostHistory,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    AVG(p.Score) AS AvgPostScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
GROUP BY 
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    AvgPostScore DESC,
    TotalPosts DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;