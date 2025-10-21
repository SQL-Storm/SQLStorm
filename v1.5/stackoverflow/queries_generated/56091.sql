-- {"query": "56091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 306} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    v.VoteTypeId, 
    lt.Name AS LinkTypeName, 
    pt.Name AS PostTypeName, 
    vt.Name AS VoteTypeName
FROM 
    Posts p
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
INNER JOIN 
    Users u ON p.OwnerUserId = u.Id
INNER JOIN 
    PostLinks pl ON p.Id = pl.PostId
INNER JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
INNER JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
INNER JOIN 
    Votes v ON p.Id = v.PostId
INNER JOIN 
    VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    AND v.VoteTypeId IN (2, 3)
    AND lt.Name = 'Linked'
    AND pt.Name = 'Question'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC;
