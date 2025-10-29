-- {"query": "6211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 310} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    STRING_AGG(DISTINCT p.Tags, ', ') WITHIN GROUP AS (ORDER BY p.Tags) AS PopularTags,
    AVG(p.Score) AS AvgPostScore,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId END) AS TotalDuplicates
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 year'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC;
