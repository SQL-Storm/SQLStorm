-- {"query": "10015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 442} 

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
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivityDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LatestGoldBadge,
    MAX(CASE WHEN b.Class = 2 THEN b.Date END) AS LatestSilverBadge,
    MAX(CASE WHEN b.Class = 3 THEN b.Date END) AS LatestBronzeBadge
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.Reputation > 10000
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC;
