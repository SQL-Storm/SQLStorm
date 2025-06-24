
SELECT TOP 10 
    P.Id AS PostId,
    P.Title,
    P.Score,
    U.DisplayName AS OwnerDisplayName,
    P.CreationDate
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
WHERE 
    P.PostTypeId = 1 
ORDER BY 
    P.CreationDate DESC;
