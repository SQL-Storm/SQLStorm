-- {"query": "45087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 396}
SELECT
    p.Id AS QuestionId,
    p.Title,
    u.DisplayName AS QuestionOwner,
    AVG(v.Score) AS AverageVoteScore,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    MAX(a.Score) AS HighestAnswerScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore
FROM 
    Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN (
    SELECT 
        pt.PostId, 
        t.TagName 
    FROM 
        UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ',')) AS pt(TagName)
    JOIN Tags t ON t.TagName = pt.TagName
) tags ON 1=1
LEFT JOIN Votes v ON v.PostId = p.Id
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate > '2015-01-01'
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, u.DisplayName
ORDER BY 
    AverageVoteScore DESC, AnswerCount DESC
LIMIT 100;
