-- {"query": "6079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 371}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName
FROM 
    Users u
LEFT JOIN 
    (
     SELECT 
         UserId, 
         MAX(Date) AS LastBadgeDate,
         Class
     FROM 
         Badges
     GROUP BY 
         UserId, Class
    ) b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
      SELECT DISTINCT
        t.TagName,
        p2.OwnerUserId AS UserId
      FROM Tags t
      JOIN Posts p2 ON p2.Tags LIKE '%' || t.TagName || '%'
    ) t ON u.Id = t.UserId
WHERE 
    (u.Reputation > 1000 OR u.Reputation IS NULL)
    AND (p.Score > 0 OR p.PostTypeId IN (1, 6, 11, 12))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class, t.TagName
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;