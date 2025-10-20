-- {"query": "32092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 265} 

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    pt.Name AS PostType,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount END), 0) AS TotalBounty
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.LastAccessDate >= (CURRENT_DATE - INTERVAL '30 days')
GROUP BY 
    u.Id, u.DisplayName, p.Id, p.Title, p.Score, p.ViewCount, pt.Name
HAVING 
    COUNT(DISTINCT v.Id) > 0
ORDER BY 
    TotalVotes DESC, TotalBounty DESC
LIMIT 100;
