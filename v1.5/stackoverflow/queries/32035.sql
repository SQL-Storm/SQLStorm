-- {"query": "32035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 282} 
SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    U.Reputation, 
    P.Id AS PostId, 
    P.Title, 
    P.Score, 
    COUNT(V.Id) AS VoteCount, 
    (SELECT COUNT(PC.Id) FROM Comments PC WHERE PC.PostId = P.Id) AS CommentCount,
    (SELECT COUNT(A.Id) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) AS AnswerCount, 
    MAX(PH.CreationDate) AS LastEdit, 
    COUNT(DISTINCT BH.Id) AS BadgeCount
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
LEFT JOIN PostHistory PH ON P.Id = PH.PostId
LEFT JOIN Badges BH ON U.Id = BH.UserId
WHERE P.PostTypeId = 1
AND P.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
AND U.Reputation > 2000
GROUP BY U.Id, U.DisplayName, U.Reputation, P.Id, P.Title, P.Score
ORDER BY VoteCount DESC, P.Score DESC, LastEdit DESC 
LIMIT 50;