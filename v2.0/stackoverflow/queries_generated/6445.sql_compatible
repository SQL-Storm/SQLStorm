SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    AVG(p.Score) AS AvgPostScore,
    SUM(v.BountyAmount) AS TotalBountyGiven,
    COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
    MAX(ph.CreationDate) AS LatestPostHistoryUpdate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months')
    AND (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) > 0
    AND (SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (10, 11, 12)) IS NULL
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) > 2
    AND COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.PostId ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;