-- {"query": "42017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 211} 

SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS VoteCount, COUNT(C.Id) AS CommentCount, SUM(P.Score) AS TotalScore, COUNT(B.Id) AS BadgeCount
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
LEFT JOIN Comments C ON P.Id = C.PostId
LEFT JOIN Badges B ON U.Id = B.UserId
WHERE P.PostTypeId = 1 AND P.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 10 AND COUNT(C.Id) > 5
ORDER BY TotalScore DESC, BadgeCount DESC, VoteCount DESC
LIMIT 100;
