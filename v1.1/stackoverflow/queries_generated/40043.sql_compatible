SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivityDate,
    AVG(u.Reputation) AS AverageReputation
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 100
    AND p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY);