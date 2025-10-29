SELECT 
    u.Id,
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(ph.CreationDate) AS LastPostHistoryUpdate,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS MostRecentPost
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 100 
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') 
    AND b.Date = (
        SELECT MAX(b2.Date) 
        FROM Badges b2 
        WHERE b2.UserId = u.Id
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 50 
    AND SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) > 100
ORDER BY 
    TotalPositiveScorePosts DESC, 
    MostRecentPost ASC
LIMIT 10;