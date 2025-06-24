
SELECT TOP 10 
    Posts.Title, 
    Users.DisplayName, 
    Posts.CreationDate, 
    Posts.Score, 
    Posts.ViewCount 
FROM 
    Posts 
JOIN 
    Users ON Posts.OwnerUserId = Users.Id 
WHERE 
    Posts.PostTypeId = 1  
ORDER BY 
    Posts.CreationDate DESC;
