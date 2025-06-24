
SELECT 
    U.DisplayName AS UserDisplayName, 
    P.Title AS PostTitle, 
    P.CreationDate AS PostCreationDate, 
    PH.CreationDate AS HistoryCreationDate, 
    PHT.Name AS HistoryTypeName 
FROM 
    Posts P 
JOIN 
    Users U ON P.OwnerUserId = U.Id 
JOIN 
    PostHistory PH ON P.Id = PH.PostId 
JOIN 
    PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id 
WHERE 
    U.Reputation > 1000 
ORDER BY 
    PH.CreationDate DESC 
OFFSET 0 ROWS 
FETCH NEXT 10 ROWS ONLY;
