-- {"query": "56023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 251} 
SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.CreationDate, 
    t.TagName, 
    COUNT(v.Id) AS VoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    PostLinks pl ON p.Id = pl.PostId
JOIN 
    Tags t ON pl.RelatedPostId = t.Id
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11)
    AND v.VoteTypeId IN (2, 3)
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.CreationDate, 
    t.TagName
ORDER BY 
    VoteCount DESC;