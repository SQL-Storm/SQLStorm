SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN p.ClosedDate ELSE p.LastActivityDate END) AS LastClosedOrActive,
    MAX(CASE WHEN pl.LinkTypeId = 1 THEN pl.CreationDate ELSE NULL END) AS FirstLinkedPost,
    MAX(CASE WHEN pl.LinkTypeId = 3 THEN pl.CreationDate ELSE NULL END) AS FirstDuplicatedPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastClosedReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment ELSE NULL END) AS LastPostNoticeAdded,
    AVG(v.BountyAmount) AS AvgBountyAmount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.LastEditDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '12 months')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;