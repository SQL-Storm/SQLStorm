-- {"query": "6728.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 315}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    MAX(b.Date) AS LastBadgeEarned,
    MAX(CASE WHEN p.LastActivityDate > p.CreationDate THEN p.LastActivityDate ELSE p.CreationDate END) AS LastActivity
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    (u.Reputation > 100 OR u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE Class = 1
    ))
AND 
    p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC, 
    LastBadgeEarned DESC;