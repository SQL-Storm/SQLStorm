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
        WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    ) AS VoteCountSubquery,
    (
        SELECT AVG(CAST(c.Score AS DOUBLE PRECISION))
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score IS NOT NULL
    ) AS AverageCommentScore,
    (
        SELECT AVG(CAST(v.BountyAmount AS DOUBLE PRECISION))
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
    p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
    AND p.Score > 10
    AND p.AnswerCount > 0
GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    pt.Name,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    u.DisplayName,
    u.Reputation,
    p.LastActivityDate
ORDER BY
    p.LastActivityDate DESC
LIMIT 1000;