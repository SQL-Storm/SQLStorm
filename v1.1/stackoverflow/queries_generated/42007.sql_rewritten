-- {"query": "42007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 201} 
SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS VoteCount, COUNT(DISTINCT C.Id) AS CommentCount, COUNT(DISTINCT PH.Id) AS HistoryCount
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
LEFT JOIN Comments C ON P.Id = C.PostId
LEFT JOIN PostHistory PH ON P.Id = PH.PostId
WHERE P.PostTypeId = 1 AND V.VoteTypeId IN (2, 3) AND C.CreationDate > (cast('2024-10-01' as date) - INTERVAL '1 year')
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 10 AND COUNT(DISTINCT C.Id) > 5
ORDER BY VoteCount DESC, CommentCount DESC
LIMIT 100;