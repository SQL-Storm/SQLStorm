-- {"query": "26035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 614} 
WITH RankedPosts AS (
  SELECT 
    P.Id, 
    P.Score, 
    P.ViewCount, 
    P.CreationDate, 
    P.LastActivityDate, 
    ROW_NUMBER() OVER (ORDER BY P.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY P.ViewCount DESC) AS ViewCountRank
  FROM Posts P
),
TopUsers AS (
  SELECT 
    U.Id, 
    U.DisplayName, 
    COUNT(DISTINCT P.Id) AS PostCount,
    SUM(P.Score) AS TotalScore,
    ROW_NUMBER() OVER (ORDER BY SUM(P.Score) DESC) AS UserRank
  FROM Users U
  JOIN Posts P ON U.Id = P.OwnerUserId
  GROUP BY U.Id, U.DisplayName
),
QuestionAnswers AS (
  SELECT 
    P.Id, 
    P.ParentId, 
    COUNT(DISTINCT A.Id) AS AnswerCount
  FROM Posts P
  LEFT JOIN Posts A ON P.Id = A.ParentId
  WHERE P.PostTypeId = 1
  GROUP BY P.Id, P.ParentId
),
UserBadges AS (
  SELECT 
    U.Id, 
    COUNT(DISTINCT B.Id) AS BadgeCount
  FROM Users U
  LEFT JOIN Badges B ON U.Id = B.UserId
  GROUP BY U.Id
)
SELECT 
  RP.Id, 
  RP.Score, 
  RP.ViewCount, 
  RP.CreationDate, 
  RP.LastActivityDate, 
  RP.ScoreRank, 
  RP.ViewCountRank,
  TU.DisplayName AS TopUser, 
  TU.PostCount, 
  TU.TotalScore, 
  TU.UserRank,
  QA.AnswerCount,
  UB.BadgeCount,
  CASE 
    WHEN RP.Score > 100 THEN 'High'
    WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
    ELSE 'Low'
  END AS ScoreCategory,
  CASE 
    WHEN RP.ViewCount > 1000 THEN 'High'
    WHEN RP.ViewCount BETWEEN 500 AND 1000 THEN 'Medium'
    ELSE 'Low'
  END AS ViewCountCategory,
  CASE 
    WHEN QA.AnswerCount > 10 THEN 'Many'
    WHEN QA.AnswerCount BETWEEN 5 AND 10 THEN 'Some'
    ELSE 'Few'
  END AS AnswerCategory,
  COALESCE(UB.BadgeCount, 0) AS BadgeCount,
  LAG(RP.Score, 1) OVER (ORDER BY RP.Score DESC) AS PrevScore,
  LEAD(RP.Score, 1) OVER (ORDER BY RP.Score DESC) AS NextScore
FROM RankedPosts RP
LEFT JOIN TopUsers TU ON RP.Id = TU.Id
LEFT JOIN QuestionAnswers QA ON RP.Id = QA.Id
LEFT JOIN UserBadges UB ON RP.Id = UB.Id
WHERE RP.Score > 50 AND RP.ViewCount > 500
ORDER BY RP.Score DESC;