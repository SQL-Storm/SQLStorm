SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId IN 
        (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND Posts.Score > 100)
    ) AS UpvotesOnHighScoredPosts,
    (SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE t.Id IN 
        (SELECT DISTINCT tg.Id FROM Tags tg JOIN Posts p2 ON tg.ExcerptPostId = p2.Id WHERE p2.OwnerUserId = u.Id)
    ) AS FavoriteTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING 
    AVG(p.Score) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;