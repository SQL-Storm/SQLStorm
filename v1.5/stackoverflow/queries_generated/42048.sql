-- {"query": "42048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 316} 

SELECT 
    p.Id AS PostId, 
    p.Title, 
    u.DisplayName AS Author, 
    COUNT(v.Id) AS TotalVotes, 
    COUNT(DISTINCT ph.UserId) AS UniqueEditors, 
    COUNT(c.Id) AS CommentCount, 
    COUNT(DISTINCT t.TagName) AS TagCount, 
    MAX(ph.CreationDate) AS LastEditedDate, 
    MAX(v.CreationDate) AS LastVoteDate
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8, 24)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    unnest(string_to_array(p.Tags, '<')) t(TagName) ON true
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(DISTINCT ph.UserId) > 2
ORDER BY 
    TotalVotes DESC, 
    TagCount DESC
LIMIT 100;
