-- {"query": "36052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 291} 
SELECT
  U.Id AS UserId,
  U.DisplayName,
  U.Reputation,
  COUNT(DISTINCT P.Id) AS PostsCreated,
  SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
  SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
  AVG(P.Score) AS AvgPostScore,
  MAX(P.CreationDate) AS LastPostCreationDate,
  (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id) AS BadgesCount,
  (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS CommentsMade,
  (SELECT COUNT(*) FROM Posts P2 WHERE P2.OwnerUserId = U.Id) AS PostsOwned
FROM
  Users U
  LEFT JOIN Posts P ON P.OwnerUserId = U.Id
  LEFT JOIN Votes V ON V.PostId = P.Id
GROUP BY
  U.Id, U.DisplayName, U.Reputation
HAVING
  COUNT(DISTINCT P.Id) > 0
ORDER BY
  Reputation DESC, PostsCreated DESC
OFFSET 0 ROWS FETCH FIRST 100 ROWS ONLY;