SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.CreationDate) AS LastPost,
    b.Class,
    b.TagBased,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS ClosedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS int) ELSE NULL END) AS CloseReasons,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '2' YEAR)
GROUP BY 
    u.DisplayName, u.Reputation, b.Class, b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalViews DESC, 
    TotalScore DESC
LIMIT 100;