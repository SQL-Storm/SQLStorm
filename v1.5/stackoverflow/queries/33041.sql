-- {"query": "33041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 239} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(EXTRACT(EPOCH FROM p.CreationDate - u.CreationDate) / 86400) AS AvgAccountAgeDaysAtPost,
    COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) AS CommentCount,
    AVG(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS AvgAnswerCount,
    MAX(p.CreationDate) AS LastPostDate
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
WHERE
    p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 10;