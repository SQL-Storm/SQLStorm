
SELECT 
    Ph.PostHistoryTypeId,
    COUNT(*) AS NumberOfChanges,
    MIN(Ph.CreationDate) AS FirstChangeDate,
    MAX(Ph.CreationDate) AS LastChangeDate,
    COUNT(DISTINCT Ph.UserId) AS UniqueUsersInvolved
FROM 
    PostHistory Ph
JOIN 
    Posts P ON Ph.PostId = P.Id
WHERE 
    P.CreationDate >= CURDATE() - INTERVAL 1 YEAR
GROUP BY 
    Ph.PostHistoryTypeId
ORDER BY 
    NumberOfChanges DESC;
