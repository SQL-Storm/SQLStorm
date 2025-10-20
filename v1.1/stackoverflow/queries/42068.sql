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
    Tags t ON t.TagName IN (
        SELECT TRIM(tag) FROM (
            SELECT regexp_split_to_table(
                CASE 
                    WHEN p.Tags LIKE '<%>' THEN SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2))
                    ELSE p.Tags
                END,
                '><'
            ) AS tag
        ) s
    )
WHERE 
    p.PostTypeId = 1 
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    u.DisplayName
HAVING 
    COUNT(v.Id) > 10 
    AND COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC
LIMIT 100;