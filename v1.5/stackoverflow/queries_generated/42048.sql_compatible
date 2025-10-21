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
    unnest(string_to_array(p.Tags, '<')) AS t(TagName) ON true
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY 
    p.Id, p.Title, u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(DISTINCT ph.UserId) > 2
ORDER BY 
    TotalVotes DESC, 
    TagCount DESC
LIMIT 100;