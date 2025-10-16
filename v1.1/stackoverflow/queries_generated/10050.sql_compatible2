SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN pv.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 3 THEN pv.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS RecentBadges
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes pv ON p.Id = pv.PostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Date, b.Name
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;