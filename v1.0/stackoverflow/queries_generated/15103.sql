SELECT 
    U.DisplayName AS User, 
    P.Title AS PostTitle, 
    P.CreationDate AS PostDate, 
    C.Text AS CommentText, 
    C.CreationDate AS CommentDate
FROM 
    Posts P
JOIN 
    Comments C ON P.Id = C.PostId
JOIN 
    Users U ON C.UserId = U.Id
WHERE 
    P.PostTypeId = 1 -- Questions
ORDER BY 
    C.CreationDate DESC
LIMIT 10;
