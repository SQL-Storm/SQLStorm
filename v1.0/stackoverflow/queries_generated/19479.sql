SELECT 
    U.DisplayName,
    P.Title,
    P.CreationDate,
    P.Score,
    C.Text AS CommentText
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON C.PostId = P.Id
WHERE 
    P.PostTypeId = 1 -- Only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
