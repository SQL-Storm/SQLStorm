-- {"query": "10080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 398} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(v.BountyAmount) AS TotalBounty,
    AVG(DATEDIFF(day, p.CreationDate, p.LastActivityDate)) AS AvgDaysToLastActivity,
    MAX(p.LastActivityDate) AS LatestActivity,
    MIN(p.CreationDate) AS EarliestPost,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS (ORDER BY t.TagName) AS PopularTags
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
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalScore DESC, 
    TotalViews DESC
LIMIT 100;
