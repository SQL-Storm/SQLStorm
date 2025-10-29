-- {"query": "6917.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 513}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS TotalDuplicates,
    MAX(u.CreationDate) AS LastAccountActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate ELSE NULL END) AS LastDeletedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate ELSE NULL END) AS LastUndeletedPost,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViewCount,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgScore DESC, 
    TotalPosts DESC;