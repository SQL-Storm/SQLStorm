
SELECT 
    U.DisplayName, 
    COUNT(P.Id) AS PostCount, 
    SUM(ISNULL(P.Score, 0)) AS TotalScore 
FROM 
    Users U 
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId 
GROUP BY 
    U.DisplayName 
ORDER BY 
    PostCount DESC 
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
