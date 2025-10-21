-- {"query": "45051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116994, "output_tokens": 20970} 
SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.ViewCount) AS MaxViewCount,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    (COUNT(DISTINCT a.Id) * 1.0 / COUNT(DISTINCT p.Id)) AS AnswerToQuestionRatio
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
LEFT JOIN 
    Votes v ON v.PostId = p.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
WHERE 
    p.PostTypeId = 1 
    AND t.Count > 1000
GROUP BY 
    t.TagName
ORDER BY 
    TotalVotes DESC, 
    AvgQuestionScore DESC
LIMIT 100;