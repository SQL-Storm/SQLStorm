SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreation,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    AVG(p.ViewCount) AS AvgViewCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR
    AND u.Reputation > 100
GROUP BY 
    u.DisplayName
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    TotalPosts DESC, 
    AvgViewCount DESC;