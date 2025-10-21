-- {"query": "58028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1519} 

SELECT U.Id, U.DisplayName, U.Reputation, 
       (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1) AS QuestionsPosted,
       (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 2) AS AnswersPosted,
       (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS CommentsMade,
       (SELECT SUM(V.VoteTypeId) FROM Votes V JOIN Posts P ON V.PostId = P.Id WHERE P.OwnerUserId = U.Id AND V.VoteTypeId IN (2,3)) AS TotalVoteImpact,
       (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
       (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId = 5) AS LastEditDate,
       AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
       RANK() OVER (ORDER BY (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = U.Id AND PostTypeId = 1) DESC) AS QuestionRank
FROM Users U
LEFT JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
WHERE U.Reputation > 10000
  AND EXISTS (SELECT 1 FROM Badges WHERE UserId = U.Id AND Class = 1)
  AND P.PostTypeId IN (1,2)
  AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
GROUP BY U.Id, U.DisplayName, U.Reputation, P.Id, P.Score, P.CreationDate
HAVING COUNT(DISTINCT P.Id) > 50
   AND SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) > 100
ORDER BY TotalVoteImpact DESC, RollingAvgScore DESC
LIMIT 100;
