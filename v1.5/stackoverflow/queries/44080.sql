SELECT 
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    /* Replace DATEDIFF with standard subtraction of dates in days */
    (DATE '2024-10-01 12:34:56' - p.CreationDate) AS PostAge,
    (DATE '2024-10-01 12:34:56' - u.CreationDate) AS UserAge,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    CASE
        WHEN p.ClosedDate IS NULL THEN 'Open'
        ELSE 'Closed'
    END AS PostStatus,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    COALESCE(p.Score, 0) AS Score,
    COALESCE(p.ViewCount, 0) AS ViewCount,
    COALESCE(COUNT(DISTINCT v.Id), 0) AS VoteCount,
    COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
    COALESCE(COUNT(DISTINCT b.Id), 0) AS BadgeCount,
    COALESCE(COUNT(DISTINCT pl.Id), 0) AS LinkCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
GROUP BY 
    p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId,
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
    p.CreationDate, p.ClosedDate, p.PostTypeId, p.AnswerCount,
    p.CommentCount, p.FavoriteCount, p.Score, p.ViewCount, u.CreationDate
ORDER BY p.CreationDate DESC
LIMIT 1000;