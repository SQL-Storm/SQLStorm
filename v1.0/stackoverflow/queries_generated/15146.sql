SELECT 
    P.Title, 
    P.CreationDate, 
    U.DisplayName AS Author, 
    C.CommentCount, 
    P.Score
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS CommentCount 
     FROM Comments 
     GROUP BY PostId) C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1  -- Only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
