SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    -- convert timestamps to epoch seconds for AVG, then convert back to timestamp
    CASE 
      WHEN SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) = 0 THEN NULL
      ELSE TO_TIMESTAMP(AVG(CASE WHEN v.VoteTypeId = 2 THEN EXTRACT(EPOCH FROM v.CreationDate) END)) 
    END AS AvgUpVoteDate,
    CASE 
      WHEN SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) = 0 THEN NULL
      ELSE TO_TIMESTAMP(AVG(CASE WHEN v.VoteTypeId = 3 THEN EXTRACT(EPOCH FROM v.CreationDate) END)) 
    END AS AvgDownVoteDate
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
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
ORDER BY 
    p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 100;