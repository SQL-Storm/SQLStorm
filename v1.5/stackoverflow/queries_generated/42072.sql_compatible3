SELECT 
    p.Id, 
    p.Title, 
    COUNT(v.Id) AS VoteCount, 
    COUNT(c.Id) AS CommentCount,
    u.DisplayName,
    u.Reputation,
    ARRAY_AGG(t.TagName) AS Tags
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
JOIN LATERAL (
    SELECT TRIM(value) AS tag
    FROM UNNEST(string_to_array(substr(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS value
) AS tag_table ON TRUE
JOIN 
    Tags t ON t.TagName = tag_table.tag
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '1 year')
GROUP BY 
    p.Id, 
    p.Title, 
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;