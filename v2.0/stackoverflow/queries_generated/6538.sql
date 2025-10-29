-- {"query": "6538.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 590} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.EmailHash,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    b.Name AS Badge,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS TopScorePost
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         ph.UserId, 
         STRING_AGG(ph.Comment, ', ') AS Comments
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 35)
     GROUP BY 
         ph.UserId) phc ON u.Id = phc.UserId
LEFT JOIN 
    (SELECT 
         t.Id, 
         STRING_AGG(t.TagName, ', ') AS TagNames
     FROM 
         Tags t
     GROUP BY 
         t.Id) t ON p.Id = t.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
    AND (u.Location IS NOT NULL OR u.EmailHash IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, u.EmailHash, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 5
ORDER BY 
    TotalBounty DESC, 
    TotalPosts DESC
LIMIT 10;
