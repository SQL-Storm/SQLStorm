-- {"query": "32082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 409} 

WITH RecentUsers AS (
    SELECT U.Id, U.DisplayName, MAX(U.CreationDate) AS MostRecentActivity
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 5000
    GROUP BY U.Id, U.DisplayName
),
PopularQuestions AS (
    SELECT P.Id, P.Title, P.AnswerCount, COUNT(DISTINCT PH.Id) AS EditCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId = 1
      AND P.ViewCount > 10000
    GROUP BY P.Id, P.Title, P.AnswerCount
    HAVING COUNT(DISTINCT PH.Id) > 3
),
ActiveBadgeUsers AS (
    SELECT U.Id, U.DisplayName, COUNT(B.Id) AS BadgeCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE B.Class = 1
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(B.Id) > 10
),
ComplexPosts AS (
    SELECT P.Id, P.Title, P.Score, P.OwnerUserId, COUNT(DISTINCT C.Id) AS CommentCount
    FROM Posts P
    JOIN Comments C ON P.Id = C.PostId
    WHERE P.Score > 50 AND P.CreationDate > '2022-01-01'
    GROUP BY P.Id, P.Title, P.Score, P.OwnerUserId
)
SELECT RU.DisplayName AS UserName, PQ.Title AS QuestionTitle, ABU.BadgeCount, CP.CommentCount
FROM RecentUsers RU
JOIN PopularQuestions PQ ON RU.Id = PQ.Id
JOIN ActiveBadgeUsers ABU ON RU.Id = ABU.Id
JOIN ComplexPosts CP ON PQ.Id = CP.Id
WHERE CP.Score > 100
ORDER BY ABU.BadgeCount DESC, CP.CommentCount DESC;
