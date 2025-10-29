SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.MaxDate) AS LatestPostHistoryEntry,
    SUM(CASE WHEN v_up.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v_down.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT PostId, MAX(CreationDate) AS MaxDate 
     FROM PostHistory 
     GROUP BY PostId) ph ON p.Id = ph.PostId
LEFT JOIN
    Votes v_up ON v_up.PostId = p.Id AND v_up.VoteTypeId = 2
LEFT JOIN
    Votes v_down ON v_down.PostId = p.Id AND v_down.VoteTypeId = 3
WHERE 
    u.Reputation > 100
    AND u.Id NOT IN (
        SELECT DISTINCT OwnerUserId 
        FROM Posts 
        WHERE PostTypeId = 1 AND ClosedDate IS NOT NULL
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    AVG(p.Score) DESC;