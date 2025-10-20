-- {"query": "45096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 220224, "output_tokens": 39137} 
SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS PostCount,
    ROUND(AVG(p.Score), 2) AS AvgPostScore,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    MAX(p.ViewCount) AS MaxViews,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (
            SELECT Id 
            FROM Posts 
            WHERE Tags LIKE '%' || t.TagName || '%'
        )
    ) AS RelatedPostLinks
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
WHERE 
    t.Count > 1000 AND 
    p.PostTypeId = 1
GROUP BY 
    t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgPostScore DESC, 
    PostCount DESC
LIMIT 50;