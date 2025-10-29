-- {"query": "6352.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 393} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         bh.PostId,
         COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.UserId END) AS CloseVotes
     FROM 
         PostHistory ph
     JOIN 
         PostHistory bh ON ph.PostId = bh.PostId AND ph.PostHistoryTypeId = 10 AND bh.PostHistoryTypeId = 10
     WHERE 
         ph.PostHistoryTypeId IN (101, 102, 103, 104, 105)
     GROUP BY 
         bh.PostId) cv ON p.Id = cv.PostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '30 days')
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 50
ORDER BY 
    AvgPostScore DESC, 
    TotalPosts DESC
LIMIT 10;
