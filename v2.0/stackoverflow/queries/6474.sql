SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS HistoryDate
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.Comment,
         ph.CreationDate,
         MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.Text END) AS InitialTitle,
         MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.Text END) AS InitialBody
     FROM 
         PostHistory ph
     GROUP BY 
         ph.PostId, ph.RevisionGUID, ph.Comment, ph.CreationDate) ph ON u.Id = ph.PostId -- corrected join to match PostHistory.PostId
LEFT JOIN 
    Posts p ON ph.PostId = p.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND (b.Class IS NULL OR b.Class = 1)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;