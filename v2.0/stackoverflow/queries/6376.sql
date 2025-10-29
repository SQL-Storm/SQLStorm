-- {"query": "6376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 344} 
SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    AVG(p.Score) AS AvgScore,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges
FROM 
    Users u
LEFT JOIN 
    Posts p 
    ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v 
    ON p.Id = v.PostId
LEFT JOIN 
    Badges b 
    ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph 
    ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE 
    p.PostTypeId IN (1, 2) 
    AND u.Reputation > 100 
    AND (u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days' OR u.LastAccessDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 50 
ORDER BY 
    TotalBounty DESC, 
    AvgScore DESC
LIMIT 10;