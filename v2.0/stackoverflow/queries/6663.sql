SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(p.LastActivityDate) AS LastActiveDate,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8 
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 5, 10, 11, 12, 13, 14, 15, 19, 20, 35)
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.PostTypeId IN (1, 2)
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalBountyAmount DESC, TotalPosts DESC
LIMIT 100;