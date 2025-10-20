-- {"query": "42011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 460} 
SELECT 
    u.DisplayName AS User,
    p.Title AS PostTitle,
    COUNT(v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(LENGTH(ph.Text)) AS AvgEditLength,
    MAX(ph.CreationDate) AS LastEditDate,
    MIN(ph.CreationDate) AS FirstEditDate,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT t.TagName) AS TagCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    u.DisplayName, p.Title
HAVING 
    COUNT(v.Id) > 0
ORDER BY 
    VoteCount DESC, TagCount DESC, UniqueEditors DESC
LIMIT 100;