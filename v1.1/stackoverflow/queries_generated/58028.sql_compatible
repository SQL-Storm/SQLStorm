SELECT U.Id, U.DisplayName, U.Reputation,
       (SELECT COUNT(*) FROM Posts P2 WHERE P2.OwnerUserId = U.Id AND P2.PostTypeId = 1) AS QuestionsPosted,
       (SELECT COUNT(*) FROM Posts P3 WHERE P3.OwnerUserId = U.Id AND P3.PostTypeId = 2) AS AnswersPosted,
       (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS CommentsMade,
       (SELECT SUM(V2.VoteTypeId) FROM Votes V2 JOIN Posts P4 ON V2.PostId = P4.Id WHERE P4.OwnerUserId = U.Id AND V2.VoteTypeId IN (2,3)) AS TotalVoteImpact,
       (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
       (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId = 5) AS LastEditDate,
       AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
       RANK() OVER (ORDER BY (SELECT COUNT(*) FROM Posts P5 WHERE P5.OwnerUserId = U.Id AND P5.PostTypeId = 1) DESC) AS QuestionRank
FROM Users U
LEFT JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON P.Id = V.PostId
WHERE U.Reputation > 10000
  AND EXISTS (SELECT 1 FROM Badges B2 WHERE B2.UserId = U.Id AND B2.Class = 1)
  AND P.PostTypeId IN (1,2)
  AND P.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
GROUP BY U.Id, U.DisplayName, U.Reputation, P.Id, P.Score, P.CreationDate, P.OwnerUserId
HAVING COUNT(DISTINCT P.Id) > 50
   AND SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) > 100
ORDER BY TotalVoteImpact DESC, RollingAvgScore DESC
LIMIT 100;