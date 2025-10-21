-- {"query": "40073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 206} 
SELECT 
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT u.Id) AS UserCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT v.PostId) AS VoteCount,
    MAX(p.Score) AS MaxScore,
    MIN(p.Score) AS MinScore,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViewCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 AND 
    u.Reputation > 1000 AND 
    b.Class = 1 AND 
    v.VoteTypeId = 2
GROUP BY 
    u.DisplayName;