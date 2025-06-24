SELECT 
    U.DisplayName AS UserDisplayName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    COUNT(C.Comments) AS CommentCount
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1 -- Only questions
GROUP BY 
    U.DisplayName, P.Title, P.CreationDate
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
