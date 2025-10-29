-- {"query": "6587.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 373}
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.ClosedDate ELSE NULL END) AS LastClosedQuestion,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(v.BountyAmount) AS MaxBounty,
    b.Name AS TopBadge
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) > 0
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgViewCount DESC, 
    MaxBounty DESC
LIMIT 100;