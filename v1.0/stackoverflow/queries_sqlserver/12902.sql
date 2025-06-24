
SELECT 
    p.Id AS PostID,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    COALESCE(v.VoteCount, 0) AS VoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON c.PostId = p.Id
LEFT JOIN 
    (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b ON b.UserId = u.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) v ON v.PostId = p.Id
WHERE 
    p.CreationDate >= DATEADD(year, -1, CAST('2024-10-01 12:34:56' AS DATETIME))
GROUP BY 
    p.Id, 
    p.Title, 
    u.DisplayName, 
    p.CreationDate, 
    p.ViewCount, 
    p.Score, 
    p.AnswerCount, 
    c.CommentCount, 
    b.BadgeCount, 
    v.VoteCount
ORDER BY 
    p.CreationDate DESC;
