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
    P.PostTypeId = 1  -- Only Questions
ORDER BY 
    PH.CreationDate DESC
LIMIT 10;  -- Limit to the most recent 10 changes
