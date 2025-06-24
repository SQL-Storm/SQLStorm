SELECT 
    U.DisplayName AS UserDisplayName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    C.Text AS CommentText,
    C.CreationDate AS CommentCreationDate
FROM 
    Posts P
JOIN 
    Comments C ON P.Id = C.PostId
JOIN 
    Users U ON C.UserId = U.Id
WHERE 
    P.PostTypeId = 1 -- Only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
