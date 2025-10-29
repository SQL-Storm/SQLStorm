SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN p.Id END) AS TotalReopenVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN p.Id END) AS TotalDeleteVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN p.Id END) AS TotalUndeleteVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicateLinks,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) AS TotalDownVotes,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswers,
    MAX(p.LastActivityDate) AS LastActiveDate,
    b.Class AS BadgeClass,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000
    AND (p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL) 
    AND (p.CreationDate >= (DATE_TRUNC('month', CAST('2024-10-01' AS DATE)) - INTERVAL '1' YEAR) OR p.CreationDate IS NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    b.Id,
    b.Class,
    b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalViews DESC
LIMIT 100;