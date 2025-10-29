-- {"query": "6588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 573}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN pl.RelatedPostId ELSE NULL END) AS TotalLinkedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN pl.RelatedPostId ELSE NULL END) AS TotalLinkedAnswers,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(ph.CreationDate) AS LastHistoryEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastCloseReason,
    AVG(v.BountyAmount) AS AvgBounty,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
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
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, u.AboutMe
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalScore DESC, 
    TotalViews DESC;