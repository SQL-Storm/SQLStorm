-- {"query": "32073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 352} 

SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    U.Reputation, 
    COUNT(DISTINCT P.Id) AS TotalPosts,
    COUNT(DISTINCT C.Id) AS TotalComments,
    SUM(VT.VoteTypeId = 2) AS TotalUpVotes,
    SUM(VT.VoteTypeId = 3) AS TotalDownVotes,
    SUM(VT.VoteTypeId = 5) AS TotalFavorites,
    B.Name AS MostCommonBadge,
    PH.Locations AS MostFrequentEditLocation
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    Votes VT ON U.Id = VT.UserId AND VT.VoteTypeId IN (2, 3, 5)
LEFT JOIN 
    (SELECT UserId, Name, COUNT(Name) AS BadgeCount 
     FROM Badges 
     GROUP BY UserId, Name) B ON U.Id = B.UserId
LEFT JOIN 
    (SELECT UserId, array_agg(PostId) AS Locations 
     FROM (SELECT UserId, PostId 
           FROM PostHistory 
           WHERE PostHistoryTypeId IN (4, 5, 6)
           GROUP BY UserId, PostId 
           ORDER BY COUNT(*) DESC LIMIT 3) Subquery 
     GROUP BY UserId) PH ON U.Id = PH.UserId
GROUP BY 
    U.Id, U.DisplayName, U.Reputation, B.Name, PH.Locations
ORDER BY 
    U.Reputation DESC, TotalPosts DESC, TotalComments DESC
LIMIT 100;
