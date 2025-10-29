-- {"query": "6724.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 469} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(ph.CreationDate) AS LastPostHistoryUpdate,
    AVG(p.ViewCount) AS AvgViewCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes,
    (
        SELECT SUM(bounty_amount) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 8
    ) AS TotalBountyAmount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id IN (t.ExcerptPostId, t.WikiPostId)
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATEADD(year, -2, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalUpVotes DESC;
