-- {"query": "56032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 231} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    u.DisplayName, 
    u.Reputation, 
    ph.Comment, 
    v.VoteTypeId, 
    vt.Name, 
    pt.Name AS PostTypeName
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
INNER JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND u.Reputation > 1000 
    AND ph.Comment LIKE '%improve%'
    AND vt.Name IN ('UpMod', 'DownMod')
    AND pt.Name IN ('Question', 'Answer')
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC
LIMIT 100;