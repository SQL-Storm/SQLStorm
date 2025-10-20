-- {"query": "56037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 232} 
SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS EditCount, 
    COUNT(DISTINCT v.VoteTypeId) AS VoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
GROUP BY 
    p.Id, p.Score, p.ViewCount, p.Title, u.DisplayName, u.Reputation
ORDER BY 
    p.Score DESC, p.ViewCount DESC
LIMIT 100;