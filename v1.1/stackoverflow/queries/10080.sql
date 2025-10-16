SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(v.BountyAmount) AS TotalBounty,
    AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0) AS AvgDaysToLastActivity,
    MAX(p.LastActivityDate) AS LatestActivity,
    MIN(p.CreationDate) AS EarliestPost,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalScore DESC, 
    TotalViews DESC
LIMIT 100;