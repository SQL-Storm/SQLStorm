SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN pv.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 3 THEN pv.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name DESC) AS BadgesEarned
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes pv ON p.Id = pv.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 100
    AND u.Id NOT IN (
        SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 3
    )
    AND u.Id NOT IN (
        SELECT DISTINCT UserId FROM Comments WHERE Text LIKE '%bug%'
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, u.AboutMe
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC, TotalUpVotes DESC
LIMIT 100;