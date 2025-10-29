SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    AVG(p.Score) AS AvgPostScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 100
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.CreationDate
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    TotalPosts DESC, 
    AvgPostScore DESC
LIMIT 100;