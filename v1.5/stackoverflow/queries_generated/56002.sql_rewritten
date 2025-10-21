-- {"query": "56002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 200} 
SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS PostCount, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount, 
    AVG(p.Score) AS AveragePostScore
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
INNER JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND p.Score > 0 
    AND v.VoteTypeId IN (2, 3)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    PostCount DESC, 
    UpVoteCount DESC, 
    AveragePostScore DESC
LIMIT 100;