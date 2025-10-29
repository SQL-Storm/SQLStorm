SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    MAX(p.LastActivityDate) AS LastActivityDate,
    AVG(p.ViewCount) AS AvgViewCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    b.Name AS BadgeName,
    b.Class,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    (u.Reputation > 10000 OR u.Reputation IS NULL)
    AND (p.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
    AND (ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    b.Id,
    b.Name,
    b.Class,
    b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    AVG(p.Score) DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;