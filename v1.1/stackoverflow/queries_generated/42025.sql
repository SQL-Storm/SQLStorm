-- {"query": "42025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 332} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    u.DisplayName AS OwnerName, 
    u.Reputation, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(ph.Id) AS HistoryCount, 
    (SELECT COUNT(*)
     FROM PostLinks pl
     WHERE pl.PostId = p.Id) AS LinkCount,
    (SELECT COUNT(*)
     FROM Tags t
     WHERE t.Id IN (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')))) AS TagCount
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
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id, 
    u.Id
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;
