SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.CreationDate) AS LastPost,
    b.Class,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
     SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.CreationDate,
         ph.UserId,
         ph.UserDisplayName,
         ph.Comment,
         ph.Text
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35)
    ) ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (
        SELECT DISTINCT UserId FROM Comments
    )
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Id,
    b.Class,
    b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 10 
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalViews DESC;