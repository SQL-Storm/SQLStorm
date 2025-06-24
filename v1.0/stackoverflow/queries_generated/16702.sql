SELECT 
    P.Id AS PostId, 
    P.Title AS PostTitle, 
    U.DisplayName AS OwnerDisplayName, 
    P.CreationDate AS PostCreationDate, 
    P.ViewCount, 
    P.Score
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
WHERE 
    P.PostTypeId = 1 -- Only questions
ORDER BY 
    P.CreationDate DESC
LIMIT 10;
