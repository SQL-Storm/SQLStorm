-- {"query": "42058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 242} 

SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    AVG(LENGTH(ph.Text)) AS AvgEditLength, 
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypes
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1 
AND 
    p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    u.DisplayName
HAVING 
    COUNT(v.Id) > 0 
AND 
    COUNT(DISTINCT ph.UserId) > 0
ORDER BY 
    TotalVotes DESC, 
    UniqueEditors DESC, 
    AvgEditLength DESC
LIMIT 100;
