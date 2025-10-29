SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUser,
    MAX(v.BountyAmount) AS MaxBounty,
    b.Name AS TopBadge,
    t.MostUsedTag AS MostUsedTag
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Badges b ON u.Id = b.UserId AND b.Class = 1
LEFT JOIN (
    SELECT 
        pt.OwnerUserId AS OwnerUserId,
        t1.TagName AS MostUsedTag,
        COUNT(*) AS cnt
    FROM 
        Tags t1
    JOIN 
        Posts pt ON t1.ExcerptPostId = pt.Id
    GROUP BY 
        pt.OwnerUserId, t1.TagName
) t ON t.OwnerUserId = u.Id
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
    u.DisplayName,
    u.Id,
    u.Reputation,
    u.CreationDate,
    b.Name,
    t.MostUsedTag
HAVING 
    COUNT(DISTINCT p.Id) > 1000
ORDER BY 
    MaxReputation DESC, 
    TotalPosts DESC;