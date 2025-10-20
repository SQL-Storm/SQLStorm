SELECT 
    p.Id AS PostId, 
    p.PostTypeId, 
    p.AcceptedAnswerId, 
    p.ParentId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    p.AnswerCount, 
    p.CommentCount AS PostCommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    COUNT(pl.Id) AS RelatedPostLinkCount, 
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount, 
    COUNT(b.Id) AS BadgeCount, 
    SUM(u.Reputation) AS TotalUserReputation
FROM Posts p
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.CreationDate BETWEEN DATE '2022-01-01' AND DATE '2022-12-31'
GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.AcceptedAnswerId, 
    p.ParentId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate
ORDER BY p.ViewCount DESC
LIMIT 1000;