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
        SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0)
             - COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)
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