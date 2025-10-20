-- {"query": "41094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 317} 

SELECT 
    U.DisplayName AS UserDisplayName,
    P.Id AS PostId,
    P.Title AS PostTitle,
    COUNT(V.Id) AS TotalVotes,
    AVG(V.BountyAmount) AS AverageBountyAmount,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN V.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    MAX(C.CreationDate) AS LatestCommentDate,
    COUNT(DISTINCT C.Id) AS TotalComments
FROM 
    Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
WHERE 
    P.PostTypeId = 1 AND P.CreationDate > '2020-01-01'
GROUP BY 
    U.DisplayName, P.Id, P.Title
HAVING 
    COUNT(V.Id) > 10 AND COUNT(DISTINCT C.Id) > 5
ORDER BY 
    TotalVotes DESC, AverageBountyAmount DESC, UpVotes DESC, DownVotes ASC, TotalComments DESC;
