-- {"query": "45075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 172050, "output_tokens": 30134} 
SELECT
    t.TagName,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(v.VoteTypeId = 2) AS UpVotes,
    SUM(v.VoteTypeId = 3) AS DownVotes,
    MAX(p.CreationDate) AS LatestPostDate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%>' || t.TagName || '<%'
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND u.Reputation > 1000
    AND p.CreationDate > CURRENT_DATE - INTERVAL '365 days'
GROUP BY 
    t.TagName, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    PostCount DESC, AvgPostScore DESC
LIMIT 100;