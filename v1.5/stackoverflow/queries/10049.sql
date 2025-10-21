SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LatestPostHistoryEntry,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS TotalUpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS TotalDownVotes,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.Score) DESC) AS TopScorePostRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId IN (1, 2) AND 
    p.LastActivityDate > p.CreationDate AND 
    u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgPostScore DESC, 
    TotalUpVotes DESC
LIMIT 100;