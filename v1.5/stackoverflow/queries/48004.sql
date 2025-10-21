SELECT
    pt.Name AS PostType,
    COUNT(p.Id) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    AVG(p.ViewCount) AS AverageViewCount,
    AVG(p.AnswerCount) AS AverageAnswerCount,
    AVG(p.CommentCount) AS AverageCommentCount,
    AVG(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS PercentageClosed,
    SUM(CASE WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END) AS PostsWithFavorites,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.CreationDate) AS LatestPostDate,
    AVG(CAST(EXTRACT(epoch FROM p.CreationDate) AS DOUBLE PRECISION)) AS AverageUnixTimestamp
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE
    p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
    AND p.CreationDate <= cast('2024-10-01' as date)
GROUP BY
    pt.Name
HAVING
    COUNT(p.Id) > 100
ORDER BY
    TotalPosts DESC;