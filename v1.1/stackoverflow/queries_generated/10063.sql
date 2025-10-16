-- {"query": "10063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 499} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedAnswerId,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN u.Id END) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
    MAX(v.BountyAmount) AS HighestBounty,
    AVG(p.Score) AS AvgScore,
    STRING_AGG(t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC
LIMIT 100;
