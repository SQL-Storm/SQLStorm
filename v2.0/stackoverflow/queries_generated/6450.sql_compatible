SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount,0) ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS LastEditDate
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        PostId, 
        MAX(Id) AS MaxId
     FROM 
        PostHistory
     GROUP BY 
        PostId) phmax ON p.Id = phmax.PostId
LEFT JOIN 
    PostHistory ph ON phmax.PostId = ph.PostId AND phmax.MaxId = ph.Id
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
    AND p.Score > 0
    AND (ph.PostHistoryTypeId = 10 OR ph.PostHistoryTypeId = 11)
    AND t.TagName LIKE 'SQL%'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Class, t.TagName, ph.RevisionGUID, ph.Comment, ph.CreationDate
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5
ORDER BY 
    u.Reputation DESC, 
    TotalScore DESC
LIMIT 100;