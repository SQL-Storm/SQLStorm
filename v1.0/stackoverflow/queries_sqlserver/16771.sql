
SELECT 
    U.DisplayName,
    P.Title,
    P.Score,
    P.CreationDate,
    C.Text AS CommentText,
    C.CreationDate AS CommentDate
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1  
ORDER BY 
    P.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
