-- {"query": "56010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 263} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.Text, 
    u.Reputation, 
    u.DisplayName, 
    u.LastAccessDate, 
    v.VoteTypeId, 
    v.UserId, 
    t.TagName
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
    Tags t ON pl.RelatedPostId = t.WikiPostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11) 
    AND v.VoteTypeId = 2 
    AND u.Reputation > 1000 
    AND t.Count > 100 
    AND pl.LinkTypeId = 1
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC
LIMIT 100;
