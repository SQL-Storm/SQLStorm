-- {"query": "6813.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 470} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    AVG(p.Score) AS AvgPostScore,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    b.Name AS TopBadge,
    t.TagName AS MostUsedTag
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         UserId, 
         Name, 
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
     FROM 
         Badges) b_ranked ON u.Id = b_ranked.UserId AND b_ranked.rn = 1
LEFT JOIN 
    Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
LEFT JOIN 
    (SELECT 
         p.OwnerUserId, 
         STRING_AGG(t.TagName, ', ') AS TagNames
     FROM 
         Posts p
     JOIN 
         Tags t ON t.Id = ANY(STRING_TO_ARRAY(p.Tags, '><'))
     GROUP BY 
         p.OwnerUserId) t ON u.Id = t.OwnerUserId
WHERE 
    (u.Reputation > 1000 OR u.Reputation IS NULL)
    AND (p.Score > 0 OR p.Score IS NULL)
    AND (v.BountyAmount > 0 OR v.BountyAmount IS NULL)
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgPostScore DESC, 
    TotalBountyAmount DESC;
