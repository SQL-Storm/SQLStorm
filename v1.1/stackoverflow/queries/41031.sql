-- {"query": "41031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 449} 
SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation, 
    u.CreationDate AS UserCreationDate, 
    COUNT(DISTINCT v.Id) AS TotalVotes, 
    AVG(v.BountyAmount) AS AvgBountyAmount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 1 THEN v.UserId END) AS AcceptedVotes, 
    COUNT(DISTINCT c.Id) AS CommentCount, 
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
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
WHERE 
    p.PostTypeId IN (1, 2) 
    AND p.CreationDate > '2020-01-01'
GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.CreationDate ASC
LIMIT 100;