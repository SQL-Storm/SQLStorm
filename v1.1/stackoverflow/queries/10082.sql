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
         ph_inner.PostId,
         ph_inner.RevisionGUID,
         ph_inner.CreationDate,
         ph_inner.Comment,
         ph_inner.UserId
     FROM 
         PostHistory ph_inner
     WHERE 
         ph_inner.PostHistoryTypeId IN (1, 10, 11, 12, 13, 14, 15, 19, 20, 35)
     ) ph ON u.Id = ph.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
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
    ph.PostId,
    ph.RevisionGUID,
    ph.CreationDate,
    ph.Comment
HAVING 
    AVG(p.Score) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;