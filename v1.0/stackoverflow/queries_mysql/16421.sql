
SELECT 
    Users.Id AS UserId,
    Users.DisplayName,
    Users.Reputation,
    Posts.Title,
    Posts.CreationDate,
    Posts.ViewCount,
    Posts.AnswerCount,
    Posts.Score
FROM 
    Users
JOIN 
    Posts ON Users.Id = Posts.OwnerUserId
WHERE 
    Posts.PostTypeId = 1 
GROUP BY 
    Users.Id,
    Users.DisplayName,
    Users.Reputation,
    Posts.Title,
    Posts.CreationDate,
    Posts.ViewCount,
    Posts.AnswerCount,
    Posts.Score
ORDER BY 
    Posts.CreationDate DESC
LIMIT 10;
