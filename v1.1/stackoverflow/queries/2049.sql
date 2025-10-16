WITH CTE_Top_Active_Users AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC, COUNT(DISTINCT C.Id) DESC) AS Rank
    FROM 
        Users U
        LEFT JOIN Posts P ON U.Id = P.OwnerUserId
        LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE 
        P.CreationDate > DATE '2022-01-01'
        AND U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.CreationDate,
    U.Reputation,
    B.Name AS BadgeName,
    B.Date AS BadgeDate,
    CTE_Top_Active_Users.TotalPosts,
    CTE_Top_Active_Users.TotalComments,
    CASE 
        WHEN V.VoteTypeId = 2 THEN 'Upvote'
        WHEN V.VoteTypeId = 3 THEN 'Downvote'
        ELSE 'Other'
    END AS VoteType,
    SUM(CASE WHEN V.BountyAmount IS NOT NULL THEN V.BountyAmount ELSE 0 END) AS TotalBountyAmount
FROM 
    Users U
    INNER JOIN CTE_Top_Active_Users ON U.Id = CTE_Top_Active_Users.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
WHERE 
    CTE_Top_Active_Users.Rank <= 5
GROUP BY 
    U.Id, U.DisplayName, U.CreationDate, U.Reputation, B.Name, B.Date, V.VoteTypeId,
    CTE_Top_Active_Users.TotalPosts, CTE_Top_Active_Users.TotalComments, CTE_Top_Active_Users.Rank
ORDER BY 
    CTE_Top_Active_Users.Rank, U.Reputation DESC, TotalBountyAmount DESC;