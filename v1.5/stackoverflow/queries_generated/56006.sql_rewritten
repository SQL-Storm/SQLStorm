-- {"query": "56006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 238} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    u.Reputation, 
    u.DisplayName, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    v.VoteTypeId, 
    t.TagName
FROM 
    Posts p
INNER JOIN 
    Users u ON p.OwnerUserId = u.Id
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
INNER JOIN 
    Votes v ON p.Id = v.PostId
INNER JOIN 
    PostLinks pl ON p.Id = pl.PostId
INNER JOIN 
    Tags t ON pl.RelatedPostId = t.Id
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND u.Reputation > 1000 
    AND ph.PostHistoryTypeId = 10 
    AND v.VoteTypeId = 2 
    AND t.TagName = 'sql'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC;