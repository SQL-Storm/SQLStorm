
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    ph.CreationDate AS LastHistoryDate,
    ph.Comment AS LastHistoryComment
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.CreationDate >= '2023-01-01' 
GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    u.DisplayName,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    ph.CreationDate,
    ph.Comment
ORDER BY 
    p.CreationDate DESC
LIMIT 100;
