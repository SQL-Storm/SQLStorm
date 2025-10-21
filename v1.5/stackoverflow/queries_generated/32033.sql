-- {"query": "32033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 265} 

SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    COUNT(DISTINCT C.Id) AS TotalComments,
    COUNT(DISTINCT B.Id) AS TotalBadges
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId AND V.UserId = U.Id
LEFT JOIN 
    VoteTypes VT ON V.VoteTypeId = VT.Id
GROUP BY 
    U.Id, U.DisplayName
HAVING 
    SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) > 100
    AND SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) < 50
ORDER BY 
    TotalUpVotes DESC, 
    TotalPosts DESC;
