-- {"query": "56058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 321} 
SELECT 
    u.DisplayName, 
    p.Title, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS EditCount, 
    COUNT(DISTINCT v.VoteTypeId) AS VoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1
    AND ph.PostHistoryTypeId IN (4, 5, 6)
    AND v.VoteTypeId IN (2, 3)
GROUP BY 
    u.DisplayName, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount
ORDER BY 
    EditCount DESC, 
    VoteCount DESC, 
    UpVotes DESC, 
    DownVotes DESC, 
    p.Score DESC, 
    p.ViewCount DESC, 
    p.AnswerCount DESC, 
    p.CommentCount DESC, 
    p.FavoriteCount DESC
LIMIT 100;