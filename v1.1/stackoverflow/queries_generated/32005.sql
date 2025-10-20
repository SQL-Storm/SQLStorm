-- {"query": "32005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 268} 

SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    COUNT(DISTINCT P.Id) AS TotalPosts, 
    COUNT(DISTINCT C.Id) AS TotalComments, 
    COUNT(DISTINCT V.Id) AS TotalVotes,
    SUM(CASE WHEN VT.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN VT.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
    AVG(P.Score) AS AvgPostScore,
    MAX(P.CreationDate) AS LastPostDate,
    COUNT(DISTINCT B.Id) AS TotalBadges
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    Votes V ON U.Id = V.UserId
LEFT JOIN 
    VoteTypes VT ON V.VoteTypeId = VT.Id
LEFT JOIN 
    Badges B ON U.Id = B.UserId
WHERE 
    U.Reputation > 1000
GROUP BY 
    U.Id, U.DisplayName
ORDER BY 
    TotalPosts DESC, TotalComments DESC, TotalBadges DESC
LIMIT 
    100;
