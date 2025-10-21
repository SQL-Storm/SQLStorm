-- {"query": "14067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 158780, "output_tokens": 67831} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS CommentCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 2
    ) AS UpvoteCount,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
        AND v.VoteTypeId = 3
    ) AS DownvoteCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
        ELSE 0
    END AS HasAcceptedAnswer,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM Posts a
            WHERE a.ParentId = p.Id
            AND a.PostTypeId = 2
        ),
        0
    ) AS AnswerCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = p.Id
            AND pl.LinkTypeId = 3
        ),
        0
    ) AS DuplicateCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id
            AND ph.PostHistoryTypeId = 10
        ),
        0
    ) AS CloseVoteCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM Votes v
            WHERE v.PostId = p.Id
            AND v.VoteTypeId = 5
        ),
        0
    ) AS FavoriteCount,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = p.OwnerUserId
            AND b.Name IN ('Famous Question', 'Famous Answer')
        ),
        0
    ) AS FamousBadgeCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.CreationDate DESC
LIMIT 100;