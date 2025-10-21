-- {"query": "52007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 162} 
SELECT 
    t.TagName,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT v.Id) AS TotalVotes
FROM 
    Tags t
JOIN 
    Posts q ON t.Id IN (SELECT UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), ''><''))::int)
WHERE 
    q.PostTypeId = 1
    AND q.CreationDate >= '2015-01-01'
GROUP BY 
    t.Id, t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgScore DESC, TotalViews DESC
LIMIT 20;