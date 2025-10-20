SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS CommentCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS LinkCount,
    (
        SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS UpVoteCount,
    (
        SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
        FROM Votes v
        WHERE v.PostId = p.Id
    ) AS DownVoteCount,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostSequence
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.CreationDate >= DATE '2023-01-01' AND p.CreationDate < DATE '2024-01-01'
    AND p.Score > 0
    AND p.ViewCount > 1000
GROUP BY
    p.Id,
    pt.Name,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName,
    u.Reputation,
    p.PostTypeId,
    p.OwnerUserId
ORDER BY
    p.CreationDate DESC
LIMIT 1000;