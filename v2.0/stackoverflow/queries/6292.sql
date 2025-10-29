-- {"query": "6292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 757}
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS TotalDuplicates,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId END) AS TotalBadges,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeletedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.Comment END) AS LastLockedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.Comment END) AS LastUnlockedPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 101 THEN ph.Comment END) AS LastCloseReasonV2,
    MAX(CASE WHEN ph.PostHistoryTypeId = 102 THEN ph.Comment END) AS LastCloseReasonV2_102,
    MAX(CASE WHEN ph.PostHistoryTypeId = 103 THEN ph.Comment END) AS LastCloseReasonV2_103,
    MAX(CASE WHEN ph.PostHistoryTypeId = 104 THEN ph.Comment END) AS LastCloseReasonV2_104,
    MAX(CASE WHEN ph.PostHistoryTypeId = 105 THEN ph.Comment END) AS LastCloseReasonV2_105,
    MAX(CASE WHEN t.TagName = 'performance' THEN t.Count END) AS TagPerformanceCount,
    MAX(CASE WHEN t.TagName = 'benchmarking' THEN t.Count END) AS TagBenchmarkingCount,
    MAX(CASE WHEN t.TagName = 'sql' THEN t.Count END) AS TagSQLCount,
    MAX(CASE WHEN t.TagName = 'database' THEN t.Count END) AS TagDatabaseCount,
    MAX(CASE WHEN t.TagName = 'optimization' THEN t.Count END) AS TagOptimizationCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
WHERE 
    (p.ViewCount > 100 OR p.Score > 100)
    AND u.Reputation > 1000
    AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 10;