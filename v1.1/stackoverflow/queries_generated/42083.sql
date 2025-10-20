-- {"query": "42083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 262} 

SELECT 
    p.Id, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(ph.Id) AS PostHistoryCount, 
    AVG(b.Class) AS AvgBadgeClass
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    OR COUNT(c.Id) > 5
ORDER BY 
    VoteCount DESC, 
    CommentCount DESC, 
    PostHistoryCount DESC
LIMIT 100;
