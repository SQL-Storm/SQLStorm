SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    AVG(p.Score) AS AverageScore,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS MostCommonTags,
    MAX(v.BountyAmount) AS HighestBounty,
    MIN(v.BountyAmount) AS LowestBounty,
    AVG(v.BountyAmount) AS AverageBounty,
    AVG(CASE WHEN ph.PostHistoryTypeId = 10 THEN EXTRACT(EPOCH FROM ph.CreationDate) ELSE NULL END) AS AvgCloseTimeSeconds,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN EXTRACT(EPOCH FROM ph.CreationDate) ELSE NULL END) AS MaxCloseTimeSeconds,
    MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN EXTRACT(EPOCH FROM ph.CreationDate) ELSE NULL END) AS MinCloseTimeSeconds,
    COUNT(DISTINCT CASE WHEN b.TagBased IS FALSE THEN b.Id END) AS TotalNamedBadges,
    COUNT(DISTINCT CASE WHEN b.TagBased IS TRUE THEN b.Id END) AS TotalTagBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 1000 
    AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    AVG(p.Score) > 0 AND AVG(v.BountyAmount) > 0
ORDER BY 
    u.Reputation DESC;