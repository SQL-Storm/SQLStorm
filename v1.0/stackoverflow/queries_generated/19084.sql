SELECT 
    U.DisplayName,
    P.Title,
    P.CreationDate,
    P.Score,
    P.ViewCount
FROM 
    Posts P
INNER JOIN 
    Users U ON P.OwnerUserId = U.Id
WHERE 
    P.PostTypeId = 1 -- Selecting only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
