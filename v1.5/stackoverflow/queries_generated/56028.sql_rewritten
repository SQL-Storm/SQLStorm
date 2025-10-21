-- {"query": "56028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 285} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    u.Reputation, 
    u.UpVotes, 
    u.DownVotes, 
    ph.PostHistoryTypeId, 
    ph.Comment, 
    ph.Text, 
    v.VoteTypeId, 
    v.UserId, 
    v.CreationDate, 
    t.TagName
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    PostLinks pl ON p.Id = pl.PostId
JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.Score > 10 
    AND p.ViewCount > 1000 
    AND u.Reputation > 1000 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13) 
    AND v.VoteTypeId IN (1, 2, 3) 
    AND t.TagName IN ('python', 'java', 'c++')
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC
LIMIT 100;