-- {"query": "6296.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 380}
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(v.BountyAmount) AS TotalBounty,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS LastActiveRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 100
    AND u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalBounty DESC, 
    TotalPosts DESC
LIMIT 100;