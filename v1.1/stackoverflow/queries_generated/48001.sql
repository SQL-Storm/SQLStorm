-- {"query": "48001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 499} 

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
        WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    ) AS EditCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS LinkCount,
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
    p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01'
    AND p.Score > 0
    AND p.ViewCount > 1000
ORDER BY
    p.CreationDate DESC
LIMIT 1000;
