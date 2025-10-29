-- {"query": "6703.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 383} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND Posts.Score > 100)
    ) AS UpvotesOnHighScoredPosts,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags t WHERE t.Id IN 
        (SELECT DISTINCT tg.Id FROM Tags tg JOIN Posts p ON tg.ExcerptPostId = p.Id WHERE p.OwnerUserId = u.Id)
    ) AS FavoriteTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
GROUP BY 
    u.Id
HAVING 
    AVG(p.Score) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;
