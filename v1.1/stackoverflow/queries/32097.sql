SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS TotalUpVotesReceived,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS TotalDownVotesReceived,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000 AND
    u.LastAccessDate > DATE '2023-01-01'
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 10
    AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 10
ORDER BY 
    SUM(COALESCE(p.Score, 0)) DESC, COUNT(DISTINCT p.Id) DESC;