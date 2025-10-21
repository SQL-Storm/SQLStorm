-- {"query": "42031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 308} 

SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(DISTINCT t.TagName) AS TagCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8, 11, 24, 31, 33, 34)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')) t(TagName) ON true
WHERE 
    p.PostTypeId = 1
GROUP BY 
    p.Id, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 AND COUNT(DISTINCT ph.UserId) > 3
ORDER BY 
    TotalVotes DESC, 
    CommentCount DESC, 
    TagCount DESC
LIMIT 100;
