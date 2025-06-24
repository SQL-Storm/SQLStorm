
SELECT 
    U.DisplayName AS UserName,
    P.Title AS PostTitle,
    PH.CreationDate AS HistoryDate,
    P.Score,
    P.ViewCount
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
JOIN 
    PostHistory PH ON P.Id = PH.PostId
WHERE 
    PH.PostHistoryTypeId IN (4, 5) 
GROUP BY 
    U.DisplayName, P.Title, PH.CreationDate, P.Score, P.ViewCount
ORDER BY 
    PH.CreationDate DESC
LIMIT 10;
