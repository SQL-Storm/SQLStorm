
SELECT 
    Posts.Id,
    Posts.Title,
    Users.DisplayName AS OwnerDisplayName,
    Posts.CreationDate,
    Posts.Score,
    Posts.ViewCount
FROM 
    Posts
JOIN 
    Users ON Posts.OwnerUserId = Users.Id
WHERE 
    Posts.PostTypeId = 1
GROUP BY 
    Posts.Id,
    Posts.Title,
    Users.DisplayName,
    Posts.CreationDate,
    Posts.Score,
    Posts.ViewCount
ORDER BY 
    Posts.CreationDate DESC
LIMIT 10;
