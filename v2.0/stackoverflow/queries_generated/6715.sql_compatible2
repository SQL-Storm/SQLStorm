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
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS TotalDownVotes,
    COALESCE(SUM(b.Class), 0) AS TotalBadges,
    SUM(CASE WHEN b.TagBased = TRUE THEN CASE WHEN t.TagName IS NOT NULL THEN 1 ELSE 0 END ELSE 0 END) AS TotalTagBasedBadges,
    SUM(CASE WHEN b.TagBased = FALSE THEN CASE WHEN t.TagName IS NOT NULL THEN 1 ELSE 0 END ELSE 0 END) AS TotalNamedBadges
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
    AND (u.LastAccessDate IS NULL OR u.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR))
GROUP BY 
    u.DisplayName, u.Reputation, u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) >= 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;