
SELECT 
    U.DisplayName AS UserDisplayName,
    P.Title AS PostTitle,
    PH.PostHistoryTypeId,
    COUNT(PH.Id) AS EditCount,
    SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TitleBodyTagEdits,
    SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 12) THEN 1 ELSE 0 END) AS ClosureReopenCount,
    AVG(DATEDIFF(EPOCH, PH.CreationDate, '2024-10-01 12:34:56'::timestamp)) AS AverageTimeBetweenEdits
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
JOIN 
    PostHistory PH ON P.Id = PH.PostId
WHERE 
    PH.CreationDate >= '2024-10-01 12:34:56'::timestamp - INTERVAL '1 year'
GROUP BY 
    U.DisplayName, P.Title, PH.PostHistoryTypeId
HAVING 
    COUNT(PH.Id) > 5
ORDER BY 
    EditCount DESC, UserDisplayName ASC;
