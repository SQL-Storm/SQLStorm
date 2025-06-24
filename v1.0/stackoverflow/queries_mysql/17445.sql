
SELECT 
    P.Title, 
    P.CreationDate, 
    U.DisplayName AS OwnerDisplayName, 
    C.Score AS CommentScore
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1 
GROUP BY 
    P.Title, 
    P.CreationDate, 
    U.DisplayName, 
    C.Score
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
