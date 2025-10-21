-- {"query": "33044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 285} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    AVG(p.ViewCount) AS AverageViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueUsers,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AverageCommentScore,
    MAX(p.CreationDate) AS MostRecentPostDate,
    COUNT(DISTINCT u.Id) AS ActiveUsers,
    COUNT(DISTINCT ph.Id) AS TotalPostHistoryChanges,
    AVG(phCountPerPost) AS AvgHistoryChangesPerPost
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN (
    SELECT
        PostId,
        COUNT(*) AS phCountPerPost
    FROM
        PostHistory
    GROUP BY
        PostId
) ph_counts ON ph_counts.PostId = p.Id
WHERE
    p.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' AND cast('2024-10-01 12:34:56' as timestamp)
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 10;