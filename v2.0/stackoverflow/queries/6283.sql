SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MAX(p.LastActivityDate) AS LastPostActivity,
    b.Class,
    b.TagBased,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate,
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN cr.Name
        WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
        WHEN ph.PostHistoryTypeId = 12 THEN 'Deleted'
        WHEN ph.PostHistoryTypeId = 13 THEN 'Undeleted'
        ELSE NULL
    END AS HistoryAction
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    CloseReasonTypes cr ON ph.Comment = CAST(cr.Id AS VARCHAR)
WHERE 
    u.Reputation > 10000
    AND p.Score > 0
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    b.Id,
    b.Class,
    b.TagBased,
    ph.Id,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    cr.Name
HAVING 
    AVG(p.Score) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;