-- {"query": "33031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 300} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    MAX(p.Score) AS MaxScore,
    MIN(p.Score) AS MinScore,
    COUNT(DISTINCT u.Id) AS UniqueUsers,
    AVG(CASE WHEN c.Score IS NOT NULL THEN c.Score ELSE 0 END) AS AverageCommentScore,
    COUNT(DISTINCT c.UserId) AS UniqueCommenters,
    COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinks,
    COUNT(CASE WHEN pv.VoteTypeId = 2 THEN 1 END) AS TotalUpVotes,
    COUNT(CASE WHEN pv.VoteTypeId = 3 THEN 1 END) AS TotalDownVotes,
    DATE_TRUNC('month', p.CreationDate) AS PostMonth
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    Votes pv ON pv.PostId = p.Id
GROUP BY
    p.PostTypeId,
    pt.Name,
    DATE_TRUNC('month', p.CreationDate)
ORDER BY
    PostMonth DESC,
    TotalPosts DESC
LIMIT 100;