
SELECT TOP 10 
    P.Title, 
    U.DisplayName AS OwnerDisplayName, 
    P.ViewCount, 
    P.CreationDate 
FROM 
    Posts P 
JOIN 
    Users U ON P.OwnerUserId = U.Id 
WHERE 
    P.PostTypeId = 1 
ORDER BY 
    P.CreationDate DESC;
