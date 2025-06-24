SELECT 
    P.Title, 
    U.DisplayName AS Author, 
    P.CreationDate, 
    P.Score, 
    P.ViewCount
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
WHERE 
    P.PostTypeId = 1 -- Questions
ORDER BY 
    P.Score DESC 
LIMIT 10;
