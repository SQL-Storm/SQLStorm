-- Performance Benchmarking Query
SELECT
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    p.AnswerCount,
    p.FavoriteCount,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS HasAcceptedAnswer
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
WHERE
    p.CreationDate >= '2020-01-01' -- Filtering for posts created in 2020 and later
GROUP BY
    p.Id, u.DisplayName
ORDER BY
    p.CreationDate DESC
LIMIT 100; -- Limiting the result to the most recent 100 posts
