
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    U.DisplayName AS OwnerDisplayName,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotes,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotes,
    bh.UserId AS EditorUserId,
    bh.CreationDate AS LastEditDate
FROM 
    Posts p
LEFT JOIN 
    Users U ON p.OwnerUserId = U.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory bh ON p.LastEditorUserId = bh.UserId AND p.LastEditDate = bh.CreationDate
WHERE 
    p.CreationDate >= DATEADD(year, -1, '2024-10-01 12:34:56')
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, U.DisplayName, bh.UserId, bh.CreationDate
ORDER BY 
    p.Score DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
