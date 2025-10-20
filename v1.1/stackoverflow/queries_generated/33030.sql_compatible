SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(COALESCE(p.AnswerCount, 0)) AS AvgAnswerCount,
    MAX(p.CreationDate) AS LastPostDate,
    AVG(c_counts.CommentCount) AS AvgCommentsPerPost,
    AVG(vc.vote_count) AS AvgVotesPerPost,
    avg_votes.avg_vote_count AS AvgVoteCountGlobal
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c_counts ON p.Id = c_counts.PostId
LEFT JOIN
    (
        SELECT PostId, COUNT(*) AS vote_count
        FROM Votes
        GROUP BY PostId
    ) vc ON p.Id = vc.PostId
LEFT JOIN
    Comments c ON p.Id = c.PostId
CROSS JOIN
    (
        SELECT AVG(CAST(v.CommentCount AS DOUBLE PRECISION)) AS avg_vote_count
        FROM (
            SELECT PostId, COUNT(*) AS CommentCount
            FROM Votes
            GROUP BY PostId
        ) v
    ) avg_votes
WHERE
    p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
GROUP BY
    p.PostTypeId,
    pt.Name,
    avg_votes.avg_vote_count
ORDER BY
    TotalPosts DESC
LIMIT 10;