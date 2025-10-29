SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate ELSE NULL END) AS FirstTitleChange,
    MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.CreationDate ELSE NULL END) AS FirstBodyChange,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS FirstCloseDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS FirstReopenDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate ELSE NULL END) AS FirstDeleteDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate ELSE NULL END) AS FirstUndeleteDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.CreationDate ELSE NULL END) AS FirstLockDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.CreationDate ELSE NULL END) AS FirstUnlockDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.CreationDate ELSE NULL END) AS FirstEditSuggestApproved,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate ELSE NULL END) AS FirstPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.CreationDate ELSE NULL END) AS FirstPostNoticeRemoved,
    AVG(p.ViewCount) AS AvgViewCount,
    AVG(p.Score) AS AvgScore,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    AVG(EXTRACT(EPOCH FROM (COALESCE(p.LastEditDate, p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0) AS AvgDaysToLastEdit,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, TotalScore DESC
LIMIT 100;