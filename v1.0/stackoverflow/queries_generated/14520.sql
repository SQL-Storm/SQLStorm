-- Performance benchmarking query for the StackOverflow schema
-- This query will benchmark the retrieval of users with their most recent activity and post statistics

SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    COUNT(P.Id) AS TotalPosts,
    COUNT(C.Id) AS TotalComments,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COALESCE(MAX(P.LastActivityDate), '1970-01-01 00:00:00') AS LastActivity,
    SUM(V.VoteTypeId = 2) AS TotalUpVotes,
    SUM(V.VoteTypeId = 3) AS TotalDownVotes
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
GROUP BY 
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
ORDER BY 
    TotalPosts DESC
LIMIT 100;
