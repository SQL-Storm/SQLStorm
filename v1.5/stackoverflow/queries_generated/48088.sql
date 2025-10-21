-- {"query": "48088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 553} 

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
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2 -- Upvote
    ) AS UpvoteCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3 -- Downvote
    ) AS DownvoteCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
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
        WHERE ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
    ) AS CloseVoteCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
WHERE pt.Name IN ('Question', 'Answer')
  AND p.CreationDate >= DATE('now', '-1 year')
GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    pt.Name,
    u.DisplayName,
    u.Reputation,
    PostStatus
HAVING
    CommentCount > 5
    AND UpvoteCount > 10
    AND EditCount > 2
    AND NumberOfLinks < 5
ORDER BY
    p.CreationDate DESC
LIMIT 100;
