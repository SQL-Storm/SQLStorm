SELECT
    t.TagName,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(p.CreationDate) AS LatestPostDate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount
FROM 
    Tags t
JOIN 
    Posts p ON p.Tags LIKE '%' || '>' || t.TagName || '<' || '%'
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND u.Reputation > 1000
    AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '365 days'
GROUP BY 
    t.TagName, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    PostCount DESC, AvgPostScore DESC
LIMIT 100;