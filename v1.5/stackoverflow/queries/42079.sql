SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName AS OwnerName, 
    u.Reputation, 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    AVG(LENGTH(p.Body)) AS AvgBodyLength,
    MAX(LENGTH(p.Body)) AS MaxBodyLength,
    MIN(LENGTH(p.Body)) AS MinBodyLength,
    AVG(LENGTH(p.Title)) AS AvgTitleLength,
    MAX(LENGTH(p.Title)) AS MaxTitleLength,
    MIN(LENGTH(p.Title)) AS MinTitleLength
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    AND u.Reputation > 100
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    p.ViewCount,
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(DISTINCT ph.Id) > 1
    AND COUNT(DISTINCT c.Id) > 5
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC
LIMIT 100;