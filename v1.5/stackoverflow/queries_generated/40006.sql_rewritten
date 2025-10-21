-- {"query": "40006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 192} 
SELECT 
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT u.Id) AS UserCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    AVG(u.Reputation) AS AvgReputation,
    MAX(u.LastAccessDate) AS LatestUserActivity
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 AND 
    p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '12 months'
GROUP BY 
    EXTRACT(YEAR FROM p.CreationDate), 
    EXTRACT(MONTH FROM p.CreationDate)
ORDER BY 
    EXTRACT(YEAR FROM p.CreationDate), 
    EXTRACT(MONTH FROM p.CreationDate);