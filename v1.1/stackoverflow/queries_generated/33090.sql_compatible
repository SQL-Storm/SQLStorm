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
    SUM(COALESCE(pc.TotalComments, 0)) AS TotalComments,
    SUM(COALESCE(pu.UpVotes, 0)) AS UpVotes,
    SUM(COALESCE(pd.DownVotes, 0)) AS DownVotes
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalComments
    FROM Comments
    GROUP BY PostId
) pc ON pc.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS UpVotes
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
) pu ON pu.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS DownVotes
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
) pd ON pd.PostId = p.Id
WHERE
    p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
GROUP BY
    p.PostTypeId, pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 100;