-- {"query": "6287.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 282}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    -- emulate DISTINCT and ORDER BY in a portable way using subquery aggregation
    (SELECT STRING_AGG(b2.Name, ', ' ORDER BY b2.Date DESC)
     FROM (
       SELECT DISTINCT b3.Name, b3.Date
       FROM Badges b3
       WHERE b3.UserId = u.Id
         AND b3.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
     ) b2
    ) AS RecentBadges,
    MAX(v.BountyAmount) AS MaxBountyOffered
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
LEFT JOIN 
    Badges b ON u.Id = b.UserId AND b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
LEFT JOIN 
    Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
GROUP BY 
    u.DisplayName, u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC
LIMIT 50;