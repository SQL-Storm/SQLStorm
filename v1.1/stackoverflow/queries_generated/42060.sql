-- {"query": "42060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 161} 

SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS TotalVotes, COUNT(C.Id) AS TotalComments, AVG(P.Score) AS AvgScore
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 10 AND COUNT(C.Id) > 5
ORDER BY TotalVotes DESC, TotalComments DESC, AvgScore DESC
LIMIT 100;
