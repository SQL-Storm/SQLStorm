-- {"query": "56020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 310} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.Comment, 
    ph.Text, 
    ph.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    vt.Name AS VoteTypeName, 
    pt.Name AS PostTypeName, 
    c.Text AS CommentText, 
    c.Score AS CommentScore, 
    c.CreationDate AS CommentCreationDate
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
JOIN 
    Comments c ON p.Id = c.PostId
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND p.AnswerCount > 5 
    AND ph.PostHistoryTypeId = 10 
    AND c.Score > 5 
    AND v.VoteTypeId = 2 
    AND vt.Name = 'UpMod'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.AnswerCount DESC, 
    ph.CreationDate DESC, 
    c.CreationDate DESC
LIMIT 100;