-- {"query": "32040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 320} 

SELECT 
    U.DisplayName, 
    SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 50) THEN 1 ELSE 0 END) AS Close_Delete_Bump_Count,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    COUNT(DISTINCT C.Id) AS TotalComments,
    SUM(V.BountyAmount) AS TotalBountyAwarded,
    ROUND(AVG(P.Score), 2) AS AvgPostScore,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 1 
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 2 
    ) AS SilverBadges,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 3 
    ) AS BronzeBadges
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId
LEFT JOIN 
    Votes V ON P.Id = V.PostId AND V.VoteTypeId = 8
GROUP BY 
    U.Id, U.DisplayName
HAVING 
    COUNT(DISTINCT P.Id) > 50
ORDER BY 
    Close_Delete_Bump_Count DESC, AvgPostScore DESC;
