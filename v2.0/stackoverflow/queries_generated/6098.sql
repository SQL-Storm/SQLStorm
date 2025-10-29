-- {"query": "6098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 413} 

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
    ) AS TotalDownVotes,
    (
        SELECT STRING_AGG(t.TagName, ', ') 
        FROM Tags t 
        WHERE t.Id IN (
            SELECT Id 
            FROM PostTags 
            WHERE PostId = p.Id
        )
    ) AS Tags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > DATEADD(month, -6, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
