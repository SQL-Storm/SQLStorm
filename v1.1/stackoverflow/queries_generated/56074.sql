-- {"query": "56074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 334} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.Comment AS CloseReason, 
    u.DisplayName AS ClosedBy, 
    ph.CreationDate AS ClosedDate, 
    v.VoteTypeId, 
    vt.Name AS VoteType, 
    COUNT(DISTINCT c.Id) AS CommentCount, 
    COUNT(DISTINCT ph.Id) AS PostHistoryCount
FROM 
    Posts p
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
INNER JOIN 
    Users u ON ph.UserId = u.Id
INNER JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 6
INNER JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.Comment, 
    u.DisplayName, 
    ph.CreationDate, 
    v.VoteTypeId, 
    vt.Name
HAVING 
    p.Score > 10 AND p.ViewCount > 1000 AND p.AnswerCount > 5
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.AnswerCount DESC
LIMIT 100;
