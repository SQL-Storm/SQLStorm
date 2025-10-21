SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS CommentCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS UpvoteCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS DownvoteCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS LastEditDate,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    COUNT(DISTINCT pl.Id) AS NumberOfLinks,
    (
        SELECT COUNT(*)
        FROM PostHistory ph_closed
        WHERE ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10
    ) AS CloseVoteCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
WHERE pt.Name IN ('Question', 'Answer')
  AND p.CreationDate >= TIMESTAMP 'now' - INTERVAL '1 year'
GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    pt.Name,
    u.DisplayName,
    u.Reputation,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END
HAVING
    COUNT(DISTINCT pl.Id) > 0
    AND (
        SELECT COUNT(*) AS _cnt
        FROM Comments c
        WHERE c.PostId = p.Id
    ) > 5
    AND (
        SELECT COUNT(*) 
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) > 10
    AND (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) > 2
    AND (
        SELECT COUNT(*)
        FROM PostLinks pl2
        WHERE pl2.PostId = p.Id
    ) < 5
ORDER BY
    p.CreationDate DESC
LIMIT 100;