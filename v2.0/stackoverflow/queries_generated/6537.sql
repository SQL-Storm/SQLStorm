-- {"query": "6537.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 428} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LatestPostHistory,
    (
        SELECT STRING_AGG(TagName, ', ')
        FROM Tags t
        WHERE t.Id IN (
            SELECT DISTINCT t.Id
            FROM Posts p
            JOIN Tags t ON t.ExcerptPostId = p.Id
            WHERE p.Id = p.PostHistory.PostId
        )
    ) AS MostFrequentTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    (
        SELECT 
            ph.PostId,
            ph.CreationDate AS PostHistoryDate
        FROM 
            PostHistory ph
        WHERE 
            ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
    ) ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
