-- {"query": "56075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 234} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    u.DisplayName, 
    u.Reputation, 
    ph.CreationDate, 
    ph.Comment, 
    v.VoteTypeId, 
    lt.Name AS LinkTypeName, 
    pt.Name AS PostTypeName
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    LinkTypes lt ON p.Id = lt.Id
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13) 
    AND v.VoteTypeId IN (2, 3) 
    AND lt.Name = 'Linked'
    AND pt.Name = 'Question'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC
LIMIT 100;