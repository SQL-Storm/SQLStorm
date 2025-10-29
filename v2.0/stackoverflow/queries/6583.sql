-- {"query": "6583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 327}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LatestPostHistoryEntry,
    (
        SELECT COUNT(*) 
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS TotalVotes,
    (
        SELECT COUNT(*) 
        FROM Badges b
        WHERE b.UserId = u.Id
    ) AS TotalBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgPostScore DESC, 
    TotalPosts DESC;