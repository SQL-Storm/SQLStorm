-- {"query": "56025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 255} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    vt.Name AS VoteTypeName, 
    COUNT(v.Id) AS VoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    VoteTypes vt ON ph.PostHistoryTypeId = vt.Id
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    AND vt.Name IN ('AcceptedByOriginator', 'UpMod', 'DownMod')
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    vt.Name
ORDER BY 
    VoteCount DESC, 
    p.Score DESC, 
    p.ViewCount DESC;
