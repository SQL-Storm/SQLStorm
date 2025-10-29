-- {"query": "6822.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 514} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class AS BadgeClass,
    t.TagName
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         p.OwnerUserId, 
         STRING_AGG(t.TagName, ', ') AS TagNames
     FROM 
         Posts p
     JOIN 
         Tags t ON t.ExcerptPostId = p.Id
     GROUP BY 
         p.OwnerUserId) t ON u.Id = t.OwnerUserId
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         ph.PostHistoryTypeId,
         ph.RevisionGUID,
         ph.CreationDate,
         CASE 
             WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN JSON_EXTRACT(ph.Text, '$[0].UserId')
             ELSE NULL 
         END AS CloseReasonUserId
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)) cp ON p.Id = cp.PostId
WHERE 
    u.Reputation > 1000
    AND (u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '30' DAY) OR u.LastAccessDate IS NULL)
    AND (p.Score > 0 OR p.PostTypeId IN (1, 2))
GROUP BY 
    u.Id, b.Class
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
