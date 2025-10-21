-- {"query": "48090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 525} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostType,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    p.ClosedDate AS PostClosedDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
    ) AS CommentCountSubquery,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
    ) AS HistoryCountSubquery,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    ) AS LinkCountSubquery,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3) /* UpVotes and DownVotes */
    ) AS VoteCountSubquery,
    (
        SELECT AVG(CAST(c.Score AS REAL))
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score IS NOT NULL
    ) AS AverageCommentScore,
    (
        SELECT AVG(CAST(v.BountyAmount AS REAL))
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL
    ) AS AverageBountyAmount
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.PostTypeId = 1 /* Questions only */
    AND p.CreationDate >= DATE('now', '-365 days') /* Posts from the last year */
    AND p.Score > 10 /* Questions with more than 10 score */
    AND p.AnswerCount > 0 /* Questions that have at least one answer */
ORDER BY
    p.LastActivityDate DESC
LIMIT 1000;