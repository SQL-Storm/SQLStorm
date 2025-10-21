-- {"query": "33013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 332} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    MIN(p.CreationDate) AS EarliestCreation,
    MAX(p.CreationDate) AS LatestCreation,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueActiveUsers,
    COUNT(c.Id) AS TotalComments,
    AVG(c.Score) AS AverageCommentScore,
    COUNT(DISTINCT c.UserId) AS UniqueCommenters,
    COUNT(v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS UpvoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteExplicit,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteExplicit
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
WHERE
    p.CreationDate >= NOW() - INTERVAL '1 year'
    AND p.PostTypeId IN (1, 2)
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC;