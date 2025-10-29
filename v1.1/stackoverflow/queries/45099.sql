-- {"query": "45099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 283}
SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViewCount,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    SUM(CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) AS QuestionsWithAnswers,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.ViewCount) AS ViewCountP75
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate > '2020-01-01'
GROUP BY 
    t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgPostScore DESC, PostCount DESC
LIMIT 50;
