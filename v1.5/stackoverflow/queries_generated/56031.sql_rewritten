-- {"query": "56031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 265} 
SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.CreationDate, 
    vt.Name AS VoteTypeName, 
    COUNT(v.Id) AS VoteCount
FROM 
    Posts p
INNER JOIN 
    Users u ON p.OwnerUserId = u.Id
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
INNER JOIN 
    Votes v ON p.Id = v.PostId
INNER JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11)
    AND v.VoteTypeId IN (2, 3)
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.CreationDate, 
    vt.Name
ORDER BY 
    VoteCount DESC, 
    p.Score DESC, 
    p.ViewCount DESC;