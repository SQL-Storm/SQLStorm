SELECT 
    P.Title, 
    P.CreationDate, 
    U.DisplayName AS OwnerName, 
    C.Text AS CommentText, 
    C.CreationDate AS CommentDate
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1  -- Only select questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
