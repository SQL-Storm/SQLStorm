-- {"query": "41005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 399} 
SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT pl.Id) AS TotalLinks,
    COUNT(DISTINCT ph.Id) AS TotalHistoryChanges,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT t.Id) AS TotalTags
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
    Tags t ON p.Id = t.Id
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, u.CreationDate
ORDER BY 
    p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 100;