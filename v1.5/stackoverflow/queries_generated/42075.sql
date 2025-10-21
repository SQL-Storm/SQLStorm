-- {"query": "42075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 212} 

SELECT DISTINCT U.DisplayName, P.Title, COUNT(V.Id) AS VoteCount, COUNT(C.Id) AS CommentCount, COUNT(B.Id) AS BadgeCount
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
LEFT JOIN Comments C ON P.Id = C.PostId
LEFT JOIN Badges B ON U.Id = B.UserId
WHERE P.PostTypeId = 1 AND P.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY U.DisplayName, P.Title
HAVING COUNT(V.Id) > 0 OR COUNT(C.Id) > 0 OR COUNT(B.Id) > 0
ORDER BY VoteCount DESC, CommentCount DESC, BadgeCount DESC
LIMIT 100;
