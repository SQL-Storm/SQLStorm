-- {"query": "42059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 181} 
SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS VoteCount, AVG(P.Score) AS AvgScore, COUNT(C.Id) AS CommentCount
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1 AND V.VoteTypeId IN (2, 3) AND C.CreationDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 10 AND AVG(P.Score) > 5
ORDER BY VoteCount DESC, AvgScore DESC
LIMIT 50;