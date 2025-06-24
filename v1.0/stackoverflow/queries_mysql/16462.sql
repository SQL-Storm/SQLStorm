
SELECT 
    P.Id AS PostId, 
    P.Title, 
    P.CreationDate, 
    U.DisplayName AS OwnerDisplayName, 
    P.Score, 
    P.ViewCount 
FROM 
    Posts P 
JOIN 
    Users U ON P.OwnerUserId = U.Id 
WHERE 
    P.PostTypeId = 1  
GROUP BY 
    P.Id, 
    P.Title, 
    P.CreationDate, 
    U.DisplayName, 
    P.Score, 
    P.ViewCount 
ORDER BY 
    P.CreationDate DESC 
LIMIT 10;
