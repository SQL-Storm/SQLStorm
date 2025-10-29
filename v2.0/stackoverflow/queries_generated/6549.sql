-- {"query": "6549.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 314} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    STRING_AGG(DISTINCT b.Name, ', ') WITHIN GROUP AS (ORDER BY b.Date DESC) AS RecentBadges,
    MAX(v.BountyAmount) AS MaxBountyOffered
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    p.CreationDate >= DATEADD(year, -5, CURRENT_TIMESTAMP)
    AND (u.Reputation > 1000 OR u.Id IN (SELECT UserId FROM Badges WHERE Class = 1))
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC
LIMIT 10;
