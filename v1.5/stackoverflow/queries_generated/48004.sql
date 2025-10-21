-- {"query": "48004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 251} 
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
    AVG(JULIANDAY(p.CreationDate)) AS AverageUnixTimestamp
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE
    p.CreationDate BETWEEN DATE('now', '-1 year') AND DATE('now')
GROUP BY
    pt.Name
HAVING
    COUNT(p.Id) > 100
ORDER BY
    TotalPosts DESC;