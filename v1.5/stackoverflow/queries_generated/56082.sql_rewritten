-- {"query": "56082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 173} 
SELECT 
    u.DisplayName, 
    p.Title, 
    COUNT(DISTINCT c.Id) AS CommentCount, 
    COUNT(DISTINCT v.Id) AS VoteCount, 
    SUM(v.BountyAmount) AS TotalBountyAmount
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
INNER JOIN 
    Comments c ON p.Id = c.PostId
INNER JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND p.Score > 10 
    AND v.VoteTypeId IN (2, 3)
GROUP BY 
    u.DisplayName, 
    p.Title
ORDER BY 
    TotalBountyAmount DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;