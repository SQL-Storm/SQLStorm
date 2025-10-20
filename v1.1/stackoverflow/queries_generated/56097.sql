-- {"query": "56097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 328} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.PostHistoryTypeId, 
    ph.CreationDate, 
    ph.Comment, 
    ph.Text, 
    u.DisplayName, 
    u.Reputation, 
    v.VoteTypeId, 
    t.TagName, 
    pl.LinkTypeId, 
    pl.CreationDate
FROM 
    Posts p
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
INNER JOIN 
    Users u ON p.OwnerUserId = u.Id
INNER JOIN 
    Votes v ON p.Id = v.PostId
INNER JOIN 
    PostLinks pl ON p.Id = pl.PostId
INNER JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13) 
    AND v.VoteTypeId IN (2, 3) 
    AND pl.LinkTypeId = 1 
    AND t.Count > 100 
    AND u.Reputation > 1000 
    AND p.CreationDate > '2020-01-01' 
    AND ph.CreationDate > '2020-01-01'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.AnswerCount DESC, 
    p.CommentCount DESC, 
    p.FavoriteCount DESC;
