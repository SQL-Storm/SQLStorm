SELECT 
    u.DisplayName, 
    u.Id,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) AS Badges,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS Tags,
    MAX(p.Score) AS TopScorePostScore,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.Score) DESC) AS TopScorePostRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Votes 
        WHERE UserId IS NOT NULL 
        GROUP BY UserId
        HAVING COUNT(DISTINCT PostId) > 10
    )
GROUP BY 
    u.DisplayName, u.Id
HAVING 
    AVG(COALESCE(p.Score,0)) > 10
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;