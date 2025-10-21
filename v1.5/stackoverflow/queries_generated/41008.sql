-- {"query": "41008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 359} 

SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    AVG(v.BountyAmount) AS AverageBountyAmount,
    SUM(p.ViewCount) AS TotalViewCount,
    SUM(p.Score) AS TotalScore
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId = 1 AND p.CreationDate > '2020-01-01'
GROUP BY 
    p.Id, p.Title, p.CreationDate, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT v.Id) > 10 AND SUM(p.ViewCount) > 1000
ORDER BY 
    TotalVotes DESC, TotalViewCount DESC, TotalScore DESC
LIMIT 10;
