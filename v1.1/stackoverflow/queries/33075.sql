-- {"query": "33075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 251} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.CreationDate) AS LatestPostDate,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    AVG(p.ViewCount) AS AverageViews,
    SUM(CASE WHEN p.AnswerCount IS NULL THEN 0 ELSE p.AnswerCount END) AS TotalAnswers,
    SUM(CASE WHEN p.CommentCount IS NULL THEN 0 ELSE p.CommentCount END) AS TotalComments,
    COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 END) AS ClosedPosts,
    COUNT(CASE WHEN p.ContentLicense IS NOT NULL THEN 1 END) AS PostsWithLicense
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 10;