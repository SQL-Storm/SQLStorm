-- {"query": "42068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 323} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    u.DisplayName AS OwnerName, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(ph.Id) AS HistoryCount, 
    COUNT(b.Id) AS BadgeCount,
    STRING_AGG(t.TagName, ', ') AS Tags
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
LEFT JOIN 
    Tags t ON p.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '"><')::int[])
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;
