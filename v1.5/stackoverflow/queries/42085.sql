SELECT 
    p.Id,
    ANY_VALUE(p.Title) AS Title,
    MAX(p.Score) AS Score,
    u.DisplayName AS Author,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    COUNT(DISTINCT t.Id) AS TagCount
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
    Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON POSITION(t.TagName IN p.Tags) > 0
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
GROUP BY 
    p.Id, u.DisplayName
ORDER BY 
    MAX(p.Score) DESC, TotalVotes DESC, CommentCount DESC, EditCount DESC, BadgeCount DESC, LinkCount DESC, TagCount DESC
LIMIT 100;