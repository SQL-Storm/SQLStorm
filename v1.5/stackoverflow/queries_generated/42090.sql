-- {"query": "42090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 319} 

SELECT 
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName AS OwnerDisplayName,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    COUNT(DISTINCT t.Id) AS TotalTags
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
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id, u.DisplayName
ORDER BY 
    p.Score DESC, TotalVotes DESC, TotalComments DESC, TotalEdits DESC, TotalBadges DESC, TotalPostLinks DESC, TotalTags DESC
LIMIT 100;
