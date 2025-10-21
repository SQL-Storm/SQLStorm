SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    AVG(P.Score) AS AvgPostScore,
    COUNT(DISTINCT C.Id) AS TotalComments
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
WHERE 
    U.CreationDate >= CAST('2020-01-01' AS DATE)
    AND U.Reputation >= 1000
GROUP BY 
    U.Id, U.DisplayName
HAVING 
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) > SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END)
ORDER BY 
    TotalPosts DESC, AvgPostScore DESC
LIMIT 50;