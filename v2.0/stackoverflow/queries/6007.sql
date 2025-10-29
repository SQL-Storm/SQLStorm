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
    ph.LatestBodyGUID AS RevisionGUID,
    ph.LatestTitleComment AS Comment,
    ph.LatestBodyEditComment AS HistoryDate,
    v.VoteTypeId
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        PostId, 
        MAX(CASE WHEN PostHistoryTypeId = 2 THEN RevisionGUID END) AS LatestBodyGUID,
        MAX(CASE WHEN PostHistoryTypeId = 1 THEN Comment END) AS LatestTitleComment,
        MAX(CASE WHEN PostHistoryTypeId = 5 THEN Comment END) AS LatestBodyEditComment
     FROM 
        PostHistory
     GROUP BY 
        PostId) ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.Score > 100
    AND (u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY OR u.LastAccessDate IS NULL)
    AND (p.LastEditDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY OR p.LastEditDate IS NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    b.Class,
    t.TagName,
    ph.LatestBodyGUID,
    ph.LatestTitleComment,
    ph.LatestBodyEditComment,
    v.VoteTypeId
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC,
    MAX(p.LastActivityDate) DESC;