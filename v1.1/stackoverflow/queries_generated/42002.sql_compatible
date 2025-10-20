SELECT 
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(c.Id) AS CommentCount,
    COUNT(DISTINCT t.TagName) AS TagCount,
    MAX(ph.CreationDate) AS LastEdited,
    MAX(v.CreationDate) AS LastVoted,
    MAX(c.CreationDate) AS LastCommented,
    MAX(b.Date) AS LastBadgeEarned
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Tags t ON POSITION(t.TagName IN p.Tags) > 0
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY 
    p.Id, p.Title, p.Score, u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(v.Id) > 10
    AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    p.Score DESC, 
    COUNT(v.Id) DESC, 
    COUNT(DISTINCT ph.UserId) DESC
LIMIT 100;