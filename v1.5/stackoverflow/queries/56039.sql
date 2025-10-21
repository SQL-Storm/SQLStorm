-- {"query": "56039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 266} 
SELECT 
    u.DisplayName, 
    p.Title, 
    ph.PostHistoryTypeId, 
    pht.Name, 
    COUNT(DISTINCT v.Id) AS VoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount, 
    AVG(p.Score) AS AverageScore, 
    MAX(p.ViewCount) AS MaxViewCount
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 AND 
    p.CreationDate > '2020-01-01' AND 
    u.Reputation > 1000
GROUP BY 
    u.DisplayName, 
    p.Title, 
    ph.PostHistoryTypeId, 
    pht.Name
ORDER BY 
    VoteCount DESC, 
    AverageScore DESC, 
    MaxViewCount DESC
LIMIT 100;