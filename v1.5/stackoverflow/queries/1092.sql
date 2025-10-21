WITH UserActivity AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT P.Id) AS TotalPosts, 
        COUNT(DISTINCT C.Id) AS TotalComments, 
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    LEFT JOIN 
        Comments C ON U.Id = C.UserId AND C.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    LEFT JOIN 
        Votes V ON U.Id = V.UserId AND V.CreationDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
), RankedUsers AS (
    SELECT 
        UA.*, 
        RANK() OVER (ORDER BY UA.TotalPosts DESC, UA.TotalUpVotes DESC, UA.Reputation DESC) AS Rank
    FROM 
        UserActivity UA
)
SELECT 
    RU.DisplayName, 
    RU.Reputation, 
    RU.TotalPosts, 
    RU.TotalComments, 
    RU.TotalUpVotes, 
    RU.TotalDownVotes
FROM 
    RankedUsers RU
WHERE 
    RU.Rank <= 10
ORDER BY 
    RU.Rank;