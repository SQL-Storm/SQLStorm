-- {"query": "33077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 268} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    MAX(p.Score) AS MaxScore,
    MIN(p.Score) AS MinScore,
    COUNT(CASE WHEN p.CreationDate >= NOW() - INTERVAL '1 year' THEN 1 END) AS PostsLastYear,
    COUNT(CASE WHEN p.ViewCount > 100 THEN 1 END) AS PopularPosts,
    AVG(COALESCE(p.AnswerCount, 0)) AS AverageAnswerCount,
    COUNT(DISTINCT u.Id) AS UniqueUsers,
    AVG(u.Reputation) AS AvgReputation,
    COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCount,
    AVG(c.Score) AS AvgCommentScore,
    DATE_TRUNC('month', p.CreationDate) AS YearMonth
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE p.CreationDate >= '2022-01-01'
GROUP BY p.PostTypeId, pt.Name, YearMonth
ORDER BY p.PostTypeId, YearMonth;