-- {"query": "6240.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 458} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    b.Class,
    t.TagName,
    ph.RevisionGUID,
    ph.Comment,
    ph.CreationDate AS HistoryDate,
    v.VoteTypeId,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS TopScoreRankPerUser
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate >= DATEADD(month, -12, GETDATE())
    AND ph.PostHistoryTypeId IN (1, 2, 5, 10) 
    AND t.TagName LIKE '%SQL%'
GROUP BY 
    u.DisplayName, u.Reputation, b.Class, t.TagName, ph.RevisionGUID, ph.Comment, ph.CreationDate, v.VoteTypeId
HAVING 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) > 0
ORDER BY 
    u.Reputation DESC, 
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) DESC;
