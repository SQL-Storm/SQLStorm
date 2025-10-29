-- {"query": "6191.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 369} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    b.Name,
    b.Date AS BadgeEarnedDate,
    ph.Comment AS CloseReason,
    AVG(p.Score) AS AvgScorePerPost,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS TopScorePost
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    p.PostTypeId IN (1, 2) 
    AND u.Reputation > 100 
    AND (b.Class = 1 OR b.Class = 2 OR b.Class = 3)
    AND ph.Comment IS NOT NULL
GROUP BY 
    u.DisplayName, u.Reputation, b.Name, b.Date
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    AvgScorePerPost DESC, 
    TotalPosts DESC
LIMIT 100;
