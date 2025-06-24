-- Performance Benchmarking SQL Query

-- This query retrieves the number of posts created by each user along with their reputation.
-- It also calculates the average score of those posts and the total number of votes received.

SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COUNT(P.Id) AS TotalPosts,
    AVG(COALESCE(P.Score, 0)) AS AverageScore,
    SUM(COALESCE(V.VoteCount, 0)) AS TotalVotes
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    (SELECT 
         PostId, 
         COUNT(Id) AS VoteCount 
     FROM 
         Votes 
     GROUP BY 
         PostId) V ON P.Id = V.PostId
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
ORDER BY 
    TotalPosts DESC;
