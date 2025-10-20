-- {"query": "45010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 22940, "output_tokens": 4109} 
SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    COUNT(DISTINCT v.Id) AS VoteCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Name LIKE '%' || t.TagName || '%'
    ) AS RelatedBadgeCount
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate > '2015-01-01'
GROUP BY 
    t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgScore DESC, 
    PostCount DESC
LIMIT 50;