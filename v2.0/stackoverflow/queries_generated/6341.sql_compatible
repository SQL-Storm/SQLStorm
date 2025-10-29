SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id ELSE NULL END) AS TotalDuplicates,
    MAX(ph.CreationDate) AS LastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 100
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    TotalPosts DESC, 
    TotalUpVotes DESC;