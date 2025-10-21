-- {"query": "32061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 263} 

SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    U.Reputation, 
    P.PostCount, 
    P.CommentCount, 
    P.VoteCount, 
    P.LastActivityDate 
FROM 
    Users U
JOIN 
    (SELECT 
        OwnerUserId, 
        COUNT(DISTINCT PostId) AS PostCount, 
        COUNT(DISTINCT C.Id) AS CommentCount, 
        COUNT(DISTINCT V.Id) AS VoteCount, 
        MAX(P.LastActivityDate) AS LastActivityDate
     FROM 
        Posts P
     LEFT JOIN 
        Comments C ON P.Id = C.PostId
     LEFT JOIN 
        Votes V ON P.Id = V.PostId
     GROUP BY 
        P.OwnerUserId) P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId AND B.Class = 1
WHERE 
    U.Reputation > 1000 
    AND EXISTS (
        SELECT 
            1 
        FROM 
            Posts 
        WHERE 
            AcceptedAnswerId IS NOT NULL 
            AND OwnerUserId = U.Id)
ORDER BY 
    U.Reputation DESC, 
    P.LastActivityDate DESC;
