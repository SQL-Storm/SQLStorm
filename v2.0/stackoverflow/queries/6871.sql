-- {"query": "6871.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 748}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount,0) ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(u.LastAccessDate) AS LastAccess,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopened,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate END) AS LastUndeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.CreationDate END) AS LastLocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.CreationDate END) AS LastUnlocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate END) AS LastPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.CreationDate END) AS LastPostNoticeRemoved,
    AVG(v.BountyAmount) AS AvgBounty,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    STRING_AGG(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Title ELSE NULL END, ', ') AS Duplicates,
    STRING_AGG(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN p.Title ELSE NULL END, ', ') AS Links,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC;