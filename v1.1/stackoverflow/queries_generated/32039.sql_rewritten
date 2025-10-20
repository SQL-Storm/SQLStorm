-- {"query": "32039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 322} 
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    COUNT(DISTINCT C.Id) AS TotalComments,
    COUNT(DISTINCT PH.Id) AS TotalEdits,
    COUNT(DISTINCT V.Id) AS TotalVotesReceived,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
    SUM(COALESCE(B.BountifulBadges, 0)) AS TotalBountifulBadges
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    PostHistory PH ON U.Id = PH.UserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    (
        SELECT 
            UserId, COUNT(Id) AS BountifulBadges
        FROM 
            Badges
        WHERE 
            Name LIKE '%Bounty%'
        GROUP BY 
            UserId
    ) B ON U.Id = B.UserId
WHERE 
    U.Reputation >= 1000
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
ORDER BY 
    TotalPosts DESC, TotalUpVotesReceived DESC, U.Reputation DESC
LIMIT 100;