-- {"query": "48094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 331} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostType,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS CommentCountOnPost,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
    ) AS HistoryCountForPost,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS LinkCountForPost,
    (
        SELECT SUM(v.VoteTypeId = 2) - SUM(v.VoteTypeId = 3)
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS NetVotesOnPost
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    AND p.Score > 10
    AND pt.Name IN ('Question', 'Answer')
ORDER BY
    p.CreationDate DESC
LIMIT 1000;