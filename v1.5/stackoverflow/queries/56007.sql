-- {"query": "56007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 262} 
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
    t.TagName, 
    pt.Name AS PostType
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
JOIN 
    Users u ON ph.UserId = u.Id
JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 6
JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
JOIN 
    PostLinks pl ON p.Id = pl.PostId
JOIN 
    Tags t ON pl.RelatedPostId = t.Id
WHERE 
    p.ClosedDate IS NOT NULL AND p.Score > 0 AND p.ViewCount > 1000
ORDER BY 
    p.Score DESC, p.ViewCount DESC
LIMIT 100;