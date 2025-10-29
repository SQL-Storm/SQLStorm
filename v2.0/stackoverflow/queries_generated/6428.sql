-- {"query": "6428.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 356} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    AVG(ph.Score) AS AvgVoteScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 2
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId = 1 AND CreationDate >= NOW() - INTERVAL '1 year'
    )
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AVG(ph.Score) DESC, 
    TotalPosts DESC
LIMIT 50;
