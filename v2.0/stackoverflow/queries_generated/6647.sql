-- {"query": "6647.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 416} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(ph.CreationDate) AS LatestPostEdit,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    AVG(p.Score) AS AvgScorePerPost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Score ELSE 0 END) AS HighestAcceptedQuestionScore,
    MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS FirstClosedDate,
    MAX(CASE WHEN t.TagName LIKE '%database%' THEN p.Score ELSE 0 END) AS DatabaseTagScoreSum
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON t.Id IN (SELECT id FROM string_to_array(p.Tags, '><'))
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > NOW() - INTERVAL '30 days'
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgScorePerPost DESC, 
    TotalPosts DESC
LIMIT 100;
