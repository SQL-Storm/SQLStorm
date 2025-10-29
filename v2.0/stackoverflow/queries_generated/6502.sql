-- {"query": "6502.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 368} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.ViewCount > 100 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId END) AS TotalDuplicates,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS ORDER BY t.TagName AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= DATEADD(year, -5, CURRENT_TIMESTAMP)
    AND (p.Score > 0 OR p.PostTypeId IN (1, 2))
GROUP BY 
    u.DisplayName
HAVING 
    AVG(p.ViewCount) > 100
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;
