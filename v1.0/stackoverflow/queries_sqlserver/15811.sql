
SELECT 
    P.Id AS PostId,
    P.Title,
    P.CreationDate,
    U.DisplayName AS OwnerDisplayName,
    COUNT(C.ID) AS CommentCount
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
GROUP BY 
    P.Id, P.Title, P.CreationDate, U.DisplayName
ORDER BY 
    P.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
