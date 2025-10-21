SELECT
    p.PostTypeId,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    AVG(p.ViewCount) AS AverageViews,
    NULLIF(AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount END), 0) AS AvgAnswersPerQuestion,
    AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))) AS AvgSecondsToLastActivity,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AverageCommentScore
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
WHERE
    p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
GROUP BY
    p.PostTypeId
ORDER BY
    TotalPosts DESC
LIMIT 10;