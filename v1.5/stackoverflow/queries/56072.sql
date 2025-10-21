-- {"query": "56072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 265} 
SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    ph.PostHistoryTypeId, 
    ph.UserId, 
    ph.CreationDate AS PostHistoryCreationDate, 
    u.DisplayName, 
    u.Reputation, 
    t.TagName, 
    v.VoteTypeId, 
    v.UserId AS VoteUserId, 
    v.CreationDate AS VoteCreationDate
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Users u ON ph.UserId = u.Id
JOIN 
    Tags t ON p.Id = t.ExcerptPostId
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
    AND v.VoteTypeId IN (2, 3)
    AND u.Reputation > 1000
    AND p.CreationDate > '2020-01-01'
    AND p.CreationDate < '2022-01-01'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC;