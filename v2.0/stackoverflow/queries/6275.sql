SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopened,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate END) AS LastUndeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.CreationDate END) AS LastLocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.CreationDate END) AS LastUnlocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate END) AS LastPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.CreationDate END) AS LastPostNoticeRemoved,
    COALESCE(SUM(CASE WHEN t.TagName LIKE '%sql%' THEN 1 ELSE 0 END), 0) AS SqlTagsCount,
    COALESCE(COUNT(DISTINCT pl.RelatedPostId), 0) AS LinkedPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN vl.VoteTypeId = 1 THEN vl.PostId END), 0) AS UpVotes,
    COALESCE(COUNT(DISTINCT CASE WHEN vl.VoteTypeId = 3 THEN vl.PostId END), 0) AS DownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes vl ON p.Id = vl.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.ViewCount > 100
    AND p.Score > 0
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalBountyAmount DESC, 
    TotalPosts DESC;