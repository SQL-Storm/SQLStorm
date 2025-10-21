SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Body, 
    p.Tags, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    AVG(v.BountyAmount) AS AvgBountyAmount,
    COUNT(DISTINCT pt.TotalTags) AS TotalTags,
    COUNT(DISTINCT ph.Id) AS TotalPostHistory,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    MAX(c.CreationDate) AS LatestComment,
    MAX(ph.CreationDate) AS LatestPostHistory,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS FavoriteVotes
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT PostId, COUNT(DISTINCT TagName) AS TotalTags FROM Tags GROUP BY PostId) AS pt ON p.Id = pt.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Body, 
    p.Tags, 
    u.DisplayName, 
    u.Reputation
ORDER BY 
    p.CreationDate DESC, 
    p.Score DESC, 
    p.ViewCount DESC
LIMIT 100;