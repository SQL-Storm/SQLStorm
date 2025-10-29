-- {"query": "6058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 396}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    AVG(p.Score) AS AvgPostScore,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.UserId END) AS TotalCloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS TotalCloseReasons,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;