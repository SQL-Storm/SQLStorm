-- {"query": "6725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 375}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LastPostEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN cl.Name END) AS CloseReasonName
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    CloseReasonTypes cl ON CAST(ph.Comment AS VARCHAR) = CAST(cl.Id AS VARCHAR)
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '12 months')
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Score,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ph.Comment,
    cl.Name
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;