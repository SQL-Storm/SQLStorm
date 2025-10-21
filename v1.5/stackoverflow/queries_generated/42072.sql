-- {"query": "42072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 274} 

SELECT 
    p.Id, 
    p.Title, 
    count(v.Id) AS VoteCount, 
    count(c.Id) AS CommentCount,
    u.DisplayName,
    u.Reputation,
    array_agg(t.TagName) AS Tags
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
JOIN 
    lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')) as tag ON true
JOIN 
    Tags t ON t.TagName = tag
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate > (CURRENT_DATE - INTERVAL '1 year')
GROUP BY 
    p.Id, 
    u.Id
HAVING 
    count(v.Id) > 10 
    AND count(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;
