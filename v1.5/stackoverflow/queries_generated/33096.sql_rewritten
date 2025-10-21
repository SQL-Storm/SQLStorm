-- {"query": "33096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 154} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    NULL AS AdditionalMetrics
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years' AND cast('2024-10-01 12:34:56' as timestamp)
    AND p.PostTypeId IN (1, 2)
GROUP BY 
    p.PostTypeId, pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 50;