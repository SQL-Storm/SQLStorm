
SELECT TOP 10
    Posts.Id AS PostId,
    Posts.Title,
    Posts.CreationDate,
    Users.DisplayName AS OwnerDisplayName,
    Users.Reputation
FROM 
    Posts
JOIN 
    Users ON Posts.OwnerUserId = Users.Id
WHERE 
    Posts.PostTypeId = 1 
ORDER BY 
    Posts.CreationDate DESC;
