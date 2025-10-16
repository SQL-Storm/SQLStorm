-- {"query": "10082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 394} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    b.Name,
    ph.Comment,
    ph.RevisionGUID,
    ph.CreationDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.CreationDate,
         ph.Comment
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 10, 11, 12, 13, 14, 15, 19, 20, 35)
     ) ph ON u.Id = ph.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CURRENT_DATE - INTERVAL '1 year')
    AND EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 2
    )
GROUP BY 
    u.Id, b.Id, ph.Id
HAVING 
    AVG(p.Score) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
