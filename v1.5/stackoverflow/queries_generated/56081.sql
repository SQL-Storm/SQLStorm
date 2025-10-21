-- {"query": "56081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 198} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.Comment AS CloseReason, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation AS OwnerReputation, 
    v.VoteTypeId, 
    vt.Name AS VoteTypeName
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE 
    p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 1000
ORDER BY 
    p.Score DESC, p.ViewCount DESC
LIMIT 100;
