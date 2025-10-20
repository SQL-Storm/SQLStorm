SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.Body AS PostBody,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    AVG(EXTRACT(EPOCH FROM b.Date)) AS AvgBadgeDateEpoch,
    -- convert epoch average to timestamp in a more portable SQL: add seconds to epoch without AT TIME ZONE
    (TIMESTAMP 'epoch' + AVG(EXTRACT(EPOCH FROM b.Date)) * INTERVAL '1 second') AS AvgBadgeDate,
    COUNT(DISTINCT ba.Id) AS BadgeCount
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
LEFT JOIN 
    Badges ba ON u.Id = ba.UserId
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Body, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC, p.Score DESC, p.ViewCount DESC
LIMIT 100;