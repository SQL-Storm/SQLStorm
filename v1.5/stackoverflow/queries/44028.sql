SELECT 
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    STRING_AGG(DISTINCT CONCAT('(SELECT COUNT(*) FROM Votes v WHERE v.PostId = ', CAST(p.Id AS TEXT), ' AND v.VoteTypeId = ', CAST(vt.Id AS TEXT), ') AS ', vt.Name), ', ') AS vote_counts,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS BadgeCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS HistoryCount
FROM
    Posts p
    JOIN VoteTypes vt ON 1=1
GROUP BY
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    vt.Id,
    vt.Name
ORDER BY
    p.Score DESC,
    p.ViewCount DESC
LIMIT 100;