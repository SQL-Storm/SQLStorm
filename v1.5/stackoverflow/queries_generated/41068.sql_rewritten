-- {"query": "41068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 472} 
SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBounty,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT pl.Id) AS TotalLinks,
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
    Tags t ON p.Id = t.Id
WHERE 
    p.PostTypeId IN (1, 2) 
    AND p.CreationDate > '2020-01-01'
GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount,
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC
LIMIT 100;