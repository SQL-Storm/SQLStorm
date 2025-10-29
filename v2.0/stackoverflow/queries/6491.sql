SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(ph.CreationDate) AS LatestPostEdit,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId END) AS TotalBadges,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    AVG(p.Score) AS AvgScorePerPost
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 2
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR)
    AND (u.Location IS NOT NULL OR u.DisplayName IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, AvgScorePerPost DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;