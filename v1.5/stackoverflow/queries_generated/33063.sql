-- {"query": "33063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 244} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(CASE WHEN p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END) AS TotalViews,
    AVG(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS AverageAnswerCount,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    COUNT(c.Id) FILTER (WHERE c.Id IS NOT NULL) AS TotalComments,
    COUNT(DISTINCT v.UserId) AS ActiveVoters,
    MAX(p.CreationDate) AS LastPostDate
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
WHERE
    p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 10;