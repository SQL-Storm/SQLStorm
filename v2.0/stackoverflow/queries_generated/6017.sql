-- {"query": "6017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 407} 

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
    (SELECT 
         UserId, 
         MAX(Date) AS LastBadgeDate, 
         Class 
     FROM 
         Badges 
     GROUP BY 
         UserId, Class) b ON u.Id = b.UserId 
LEFT JOIN 
    (SELECT 
         TagName, 
         COUNT(*) AS TagCount 
     FROM 
         Tags 
     GROUP BY 
         TagName) t ON TRUE
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    u.Reputation > 10000
    AND p.Score > 0
    AND p.ViewCount > 1000
    AND p.LastEditDate > (CURRENT_DATE - INTERVAL '1 year')
    AND (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) > 5
GROUP BY 
    u.DisplayName, u.Reputation, b.Class
HAVING 
    COUNT(DISTINCT CASE WHEN ph.Comment IS NOT NULL THEN ph.Comment END) > 0
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
