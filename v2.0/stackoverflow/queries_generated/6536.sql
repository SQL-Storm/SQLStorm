-- {"query": "6536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 380} 

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
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT DISTINCT PostId, MAX(CreationDate) AS MaxDate 
     FROM PostHistory 
     GROUP BY PostId) ph ON p.Id = ph.PostId
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
    AvgPostScore DESC;
