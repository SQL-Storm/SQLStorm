-- {"query": "6453.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 369} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestActivity,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Tags t
        WHERE t.Id IN (
            SELECT TagId
            FROM PostTags pt
            WHERE pt.PostId = p.Id
        )
    ) AS Tags,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id
    ) AS LinkedPostsCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    b.Date = (SELECT MAX(Date) FROM Badges WHERE UserId = u.Id)
    AND p.CreationDate >= DATEADD(year, -1, GETDATE())
GROUP BY 
    u.DisplayName, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;
