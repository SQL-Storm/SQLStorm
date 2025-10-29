-- {"query": "6799.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 398} 

SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    MAX(v.BountyAmount) AS MaxBounty,
    b.Name AS TopBadge,
    t.TagName AS MostUsedTag
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Badges b ON u.Id = b.UserId AND b.Class = 1
LEFT JOIN 
    Tags t ON (
        SELECT 
            t1.TagName 
        FROM 
            Tags t1
        JOIN 
            Posts pt ON t1.ExcerptPostId = pt.Id
        WHERE 
            pt.OwnerUserId = u.Id
        GROUP BY 
            t1.TagName
        ORDER BY 
            COUNT(*) DESC
        LIMIT 1
    )
WHERE 
    u.Id IN (
        SELECT 
            UserId 
        FROM 
            Votes 
        WHERE 
            VoteTypeId IN (2, 3) 
        GROUP BY 
            UserId
        HAVING 
            COUNT(DISTINCT PostId) > 100
    )
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 1000
ORDER BY 
    MaxReputation DESC, 
    TotalPosts DESC;
