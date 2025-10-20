-- {"query": "56085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 342} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    u.Reputation, 
    u.DisplayName, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS EditHistoryCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(DISTINCT t.TagName) AS TagCount,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount
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
    p.PostTypeId = 1
    AND p.Score > 10
    AND p.ViewCount > 1000
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.Reputation, u.DisplayName
ORDER BY 
    p.Score DESC, p.ViewCount DESC, u.Reputation DESC;
