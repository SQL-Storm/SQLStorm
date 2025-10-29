-- {"query": "6862.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 462} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(u.LastAccessDate) AS LastAccess,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopened,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > DATEADD(month, -6, CURRENT_TIMESTAMP)
    AND (ph.PostHistoryTypeId IS NULL OR ph.PostHistoryTypeId NOT IN (10, 12))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 10
    AND AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
