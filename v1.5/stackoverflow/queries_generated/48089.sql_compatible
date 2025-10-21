SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT SUM(Score)
        FROM Comments
        WHERE PostId = p.Id
    ) AS TotalCommentScore,
    (
        SELECT COUNT(*)
        FROM Votes
        WHERE PostId = p.Id AND VoteTypeId = 2 -- UpVote
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*)
        FROM Votes
        WHERE PostId = p.Id AND VoteTypeId = 3 -- DownVote
    ) AS TotalDownVotes,
    (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    ) AS TotalEdits,
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id
        AND pl.LinkTypeId = 3 -- Duplicate Link
    ) AS DuplicateLinkCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ViewCount,
    p.Score AS PostScore,
    p.ClosedDate
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year' -- Posts created in the last year
    AND p.Score > 100 -- High scoring posts
    AND p.AnswerCount > 5 -- Posts with more than 5 answers
ORDER BY
    p.CreationDate DESC,
    p.Score DESC,
    p.AnswerCount DESC
LIMIT 100;