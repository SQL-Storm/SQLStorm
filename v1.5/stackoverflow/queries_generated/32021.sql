-- {"query": "32021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 666} 

WITH TopQuestionPosters AS (
  SELECT P.OwnerUserId, COUNT(*) AS QuestionCount
  FROM Posts P
  WHERE P.PostTypeId = 1
  GROUP BY P.OwnerUserId
  ORDER BY QuestionCount DESC
  LIMIT 10
),
TopAnswerers AS (
  SELECT P.OwnerUserId, COUNT(*) AS AnswerCount
  FROM Posts P
  WHERE P.PostTypeId = 2
  GROUP BY P.OwnerUserId
  ORDER BY AnswerCount DESC
  LIMIT 10
),
CombinedTopUsers AS (
  SELECT TQP.OwnerUserId, TQP.QuestionCount, 0 AS AnswerCount
  FROM TopQuestionPosters TQP
  UNION ALL
  SELECT TA.OwnerUserId, 0 AS QuestionCount, TA.AnswerCount
  FROM TopAnswerers TA
),
UserScore AS (
  SELECT CU.OwnerUserId, U.DisplayName, SUM(CU.QuestionCount) AS TotalQuestions, SUM(CU.AnswerCount) AS TotalAnswers
  FROM CombinedTopUsers CU
  JOIN Users U ON CU.OwnerUserId = U.Id
  GROUP BY CU.OwnerUserId, U.DisplayName
  ORDER BY (SUM(CU.QuestionCount) + SUM(CU.AnswerCount)) DESC
),
TopUserDetails AS (
  SELECT U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.UpVotes, U.DownVotes, U.Views
  FROM UserScore US
  JOIN Users U ON US.OwnerUserId = U.Id
),
TopUserPosts AS (
  SELECT P.OwnerUserId, P.Id AS PostId, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount
  FROM Posts P
  WHERE P.OwnerUserId IN (SELECT Id FROM TopUserDetails)
  ORDER BY P.Score DESC, P.ViewCount DESC
  LIMIT 50
),
UserPostInteractions AS (
  SELECT
    TUP.OwnerUserId,
    TUP.PostId,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVoteCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVoteCount
  FROM TopUserPosts TUP
  LEFT JOIN Comments C ON TUP.PostId = C.PostId
  LEFT JOIN Votes V ON TUP.PostId = V.PostId
  GROUP BY TUP.OwnerUserId, TUP.PostId
)
SELECT 
  TUD.DisplayName,
  TUD.Reputation,
  TUD.CreationDate,
  TUD.LastAccessDate,
  TUD.Location,
  TUD.UpVotes,
  TUD.DownVotes,
  TUD.Views,
  UPI.PostId,
  UPI.CommentCount,
  UPI.UpVoteCount,
  UPI.DownVoteCount
FROM TopUserDetails TUD
JOIN UserPostInteractions UPI ON TUD.Id = UPI.OwnerUserId
ORDER BY TUD.Reputation DESC, (UPI.UpVoteCount - UPI.DownVoteCount) DESC;
