
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    u.DisplayName AS OwnerDisplayName,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    (SELECT COUNT(1) FROM Posts WHERE ParentId = p.Id) AS AnswerCount,
    pt.Name AS PostTypeName,
    LISTAGG(t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName) AS Tags
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    (SELECT DISTINCT TRIM(value) AS TagName FROM LATERAL FLATTEN(INPUT => SPLIT(p.Tags, ','))) AS t ON TRUE
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName, pt.Name
ORDER BY 
    p.Score DESC
LIMIT 100;
