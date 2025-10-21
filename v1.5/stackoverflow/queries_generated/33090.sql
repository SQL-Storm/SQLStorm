-- {"query": "33090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 284} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.CreationDate) AS MostRecentPostDate,
    SUM(CASE WHEN p.ViewCount > 100 THEN 1 ELSE 0 END) AS PostsWithHighViewCount,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    AVG(COALESCE(p.AnswerCount, 0)) AS AverageAnswerCount,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE
    p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 100;