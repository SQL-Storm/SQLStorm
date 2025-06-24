SELECT 
    P.Id AS PostId, 
    P.Title, 
    P.CreationDate, 
    U.DisplayName AS OwnerName, 
    P.Score, 
    P.ViewCount, 
    P.AnswerCount 
FROM 
    Posts P 
JOIN 
    Users U ON P.OwnerUserId = U.Id 
WHERE 
    P.PostTypeId = 1 -- Questions only
ORDER BY 
    P.CreationDate DESC 
LIMIT 10;
