-- {"query": "48042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 690} 

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
    ) AS CommentCount,
    (
        SELECT SUM(v.VoteTypeId = 2) -- Count of UpVotes
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS UpVoteCount,
    (
        SELECT SUM(v.VoteTypeId = 3) -- Count of DownVotes
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS DownVoteCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits (Title, Body, Tags)
    ) AS EditCount,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS LastEditDate,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id
        AND pl.LinkTypeId = 3 -- Duplicate Links
    ) AS DuplicateLinkCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.RelatedPostId = p.Id
        AND pl.LinkTypeId = 3 -- Duplicate Links
    ) AS DuplicateOfCount,
    p.AnswerCount,
    p.ViewCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
        AND b.Class = 1 -- Gold Badges
    ) AS OwnerGoldBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
        AND b.Class = 2 -- Silver Badges
    ) AS OwnerSilverBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
        AND b.Class = 3 -- Bronze Badges
    ) AS OwnerBronzeBadgeCount
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    pt.Id = 1 -- Filter for Questions only
    AND p.CreationDate >= DATE('now', '-365 day') -- Last year
    AND p.OwnerUserId > 0 -- Exclude community user
    AND p.Score > 10 -- Posts with a reasonable score
ORDER BY
    p.CreationDate DESC
LIMIT 1000;
