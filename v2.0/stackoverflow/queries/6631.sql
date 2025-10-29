-- {"query": "6631.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 351}
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
    ph.RevisionGUID
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND p.Score > 0
    AND p.LastEditDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    AND EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.PostId = p.Id 
        AND v.VoteTypeId = 2
    )
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    b.Id,
    b.Class,
    b.Name,
    p.LastActivityDate,
    ph.Id,
    ph.Comment,
    ph.RevisionGUID
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;