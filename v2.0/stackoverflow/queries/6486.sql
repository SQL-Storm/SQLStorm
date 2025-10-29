-- {"query": "6486.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 343}
SELECT 
    u.Id,
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.Reputation) AS MinReputation,
    AVG(u.Reputation) AS AvgReputation,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(p.Score) AS TopScorePost
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN 
    Tags t ON pl.RelatedPostId = t.Id
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId = 1 
          AND CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    )
GROUP BY 
    u.Id,
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC;