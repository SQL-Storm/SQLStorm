-- {"query": "6315.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 418}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN p.Id ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 3 THEN p.Id ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReason,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    AVG(p.Score) AS AvgScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes pv ON p.Id = pv.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 1000
    AND u.Id NOT IN (SELECT AccountId FROM Users WHERE AccountId > 0)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, 
    AvgScore DESC
LIMIT 100;