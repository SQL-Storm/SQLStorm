-- {"query": "6968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 399} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE NULL END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
    MAX(p.Score) AS HighestScorePost,
    MIN(p.Score) AS LowestScorePost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(ph.CreationDate) AS LastActivityDate,
    AVG(v.BountyAmount) AS AvgBountyAmount
FROM 
    Users u
LEFT JOIN 
    Posts p 
    ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b 
    ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph 
    ON p.Id = ph.PostId
LEFT JOIN 
    Votes v 
    ON p.Id = v.PostId
LEFT JOIN 
    Tags t 
    ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 100 
    AND p.CreationDate >= DATEADD(year, -1, GETDATE())
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    AVG(p.ViewCount) > 100 
    AND COUNT(DISTINCT b.Id) > 5
ORDER BY 
    TotalPosts DESC, 
    AVG(p.Score) DESC;
