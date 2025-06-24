
SELECT 
    P.Id AS PostId,
    P.Title,
    U.DisplayName AS OwnerDisplayName,
    P.CreationDate,
    P.Score,
    P.ViewCount,
    C.Count AS CommentCount
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS Count
     FROM Comments
     GROUP BY PostId) C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1 
GROUP BY 
    P.Id, P.Title, U.DisplayName, P.CreationDate, P.Score, P.ViewCount, C.Count
ORDER BY 
    P.CreationDate DESC
OFFSET 0 ROWS 
FETCH NEXT 10 ROWS ONLY;
