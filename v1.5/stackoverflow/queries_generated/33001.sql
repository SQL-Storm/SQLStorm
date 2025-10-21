-- {"query": "33001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 384} 
SELECT
    p.PostTypeId,
    COUNT(p.Id) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.CreationDate) AS LatestPostDate,
    COUNT(DISTINCT c.Id) AS TotalComments,
    AVG(c.Score) AS AverageCommentScore,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryActions,
    COUNT(DISTINCT v.PostId) AS PostsWithVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
    COUNT(DISTINCT bl.RelatedPostId) AS TotalLinks,
    COUNT(DISTINCT t.Id) AS TotalTags,
    SUM(t.IsModeratorOnly::int) AS ModeratorOnlyTagsCount
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    PostLinks bl ON bl.PostId = p.Id
LEFT JOIN
    PostLinks bl2 ON bl2.RelatedPostId = p.Id
LEFT JOIN
    Tags t ON t.Id = p.Id
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY
    p.PostTypeId
ORDER BY
    p.PostTypeId;