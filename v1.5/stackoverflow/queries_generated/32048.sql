-- {"query": "32048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 312} 

SELECT 
    U.DisplayName AS UserName,
    P.Id AS PostId,
    P.Title AS PostTitle,
    P.Score AS PostScore,
    P.CreationDate AS PostCreationDate,
    COUNT(DISTINCT C.Id) AS TotalComments,
    COUNT(DISTINCT PL.Id) AS TotalLinks,
    COUNT(DISTINCT PV.Id) AS TotalVotes,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON C.PostId = P.Id
LEFT JOIN 
    PostLinks PL ON PL.PostId = P.Id
LEFT JOIN 
    Votes PV ON PV.PostId = P.Id
LEFT JOIN 
    Badges B ON B.UserId = U.Id
WHERE 
    P.PostTypeId = 1 
    AND P.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
GROUP BY 
    U.DisplayName, P.Id, P.Title, P.Score, P.CreationDate
HAVING 
    COUNT(DISTINCT PV.Id) > 100
ORDER BY 
    P.Score DESC, TotalVotes DESC
LIMIT 10;
