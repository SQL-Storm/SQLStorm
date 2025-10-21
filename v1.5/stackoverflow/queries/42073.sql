-- {"query": "42073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 229} 
SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS TotalVotes, COUNT(C.Id) AS TotalComments, AVG(P.Score) AS AvgScore, COUNT(B.Id) AS TotalBadges
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
LEFT JOIN Comments C ON P.Id = C.PostId
LEFT JOIN Badges B ON U.Id = B.UserId
WHERE P.PostTypeId = 1 AND V.VoteTypeId IN (2, 3) AND C.CreationDate BETWEEN DATE_TRUNC('month', cast('2024-10-01' as date)) AND cast('2024-10-01' as date)
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 10 AND COUNT(C.Id) > 5
ORDER BY TotalVotes DESC, TotalComments DESC, AvgScore DESC, TotalBadges DESC
LIMIT 100;