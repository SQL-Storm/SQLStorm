
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    GROUP_CONCAT(DISTINCT t.TagName ORDER BY t.TagName SEPARATOR ', ') AS Tags,
    COALESCE(ub.Reputation, 0) AS OwnerReputation,
    COALESCE(up.Reputation, 0) AS LastEditorReputation
FROM 
    Posts p
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Users ub ON p.OwnerUserId = ub.Id
LEFT JOIN 
    Users up ON p.LastEditorUserId = up.Id
LEFT JOIN 
    Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
WHERE 
    p.CreationDate >= '2023-10-01 12:34:56'
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, ub.Reputation, up.Reputation
ORDER BY 
    p.CreationDate DESC;
