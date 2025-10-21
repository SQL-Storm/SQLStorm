-- {"query": "43033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 397} 

SELECT 
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT B.Id) AS TotalBadges,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(P.Score) AS TotalScore,
    AVG(P.Score) AS AvgScore,
    COUNT(DISTINCT PH.Id) AS TotalPostEdits,
    COUNT(DISTINCT C.Id) AS TotalComments,
    DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
FROM 
    Users U
LEFT JOIN 
    Badges B ON U.Id = B.UserId
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN 
    Comments C ON U.Id = C.UserId
WHERE 
    U.Reputation > 1000 AND
    P.CreationDate BETWEEN DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 year') AND CURRENT_DATE
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
HAVING 
    COUNT(DISTINCT P.Id) > 10
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;
