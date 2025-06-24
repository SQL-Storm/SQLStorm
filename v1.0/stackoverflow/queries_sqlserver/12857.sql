
SELECT 
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(b.Id) AS BadgeCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.CreationDate >= CAST(DATEADD(MONTH, -1, '2024-10-01') AS DATE)
GROUP BY 
    p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate, u.Id, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC;
