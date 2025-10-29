SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class AS BadgeClass,
    t.TagName,
    ph.RevisionGUID,
    ph.CreationDate AS LastRevisionDate,
    MAX(p.Score) AS MaxPostScore,
    MAX(p.ViewCount) AS MaxPostViewCount,
    MAX(p.AnswerCount) AS MaxPostAnswerCount
FROM 
    Users u
LEFT JOIN 
    (
     SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.CreationDate,
         ph.PostHistoryTypeId,
         ph.UserId
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35)
    ) ph ON u.Id = ph.UserId
RIGHT JOIN 
    Posts p ON ph.PostId = p.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation >= 1000
    AND p.Score > 0
    AND p.ViewCount > 100
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class, t.TagName, ph.RevisionGUID, ph.CreationDate
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
ORDER BY 
    u.Reputation DESC, MAX(p.Score) DESC;