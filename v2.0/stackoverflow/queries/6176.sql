-- {"query": "6176.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 307}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    MAX(ph.CreationDate) AS LatestPostHistory,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation >= 1000
    AND p.LastActivityDate > (DATE '2024-10-01' - INTERVAL '1' YEAR)
    AND ph.PostHistoryTypeId = 10
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation
ORDER BY 
    TotalPosts DESC, 
    TotalQuestions DESC
LIMIT 100;