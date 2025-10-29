-- {"query": "4132.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1784}
WITH
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.OwnerUserId,
      p.Score,
      p.AnswerCount,
      p.Tags,
      u.DisplayName AS OwnerDisplayName,
      CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer
    FROM
      Posts AS p
      JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
  ),
  AnswerMetrics AS (
    SELECT
      ParentId,
      COUNT(Id) AS AnswerCount,
      SUM(Score) AS TotalAnswerScore,
      AVG(Score) AS AverageAnswerScore,
      MAX(CreationDate) AS LastAnswerDate
    FROM
      Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      ParentId
  ),
  CommentAnalysis AS (
    SELECT
      PostId,
      COUNT(Id) AS CommentCount,
      SUM(CASE WHEN UserId IS NOT NULL THEN 1 ELSE 0 END) AS UserCommentCount,
      SUM(CASE WHEN UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
      AVG(Score) AS AverageCommentScore
    FROM
      Comments
    GROUP BY
      PostId
  ),
  PostWithJoins AS (
    SELECT
      rq.PostId,
      rq.Title,
      rq.CreationDate AS QuestionCreationDate,
      rq.OwnerDisplayName,
      rq.Score AS QuestionScore,
      rq.AnswerCount AS QuestionAnswerCount,
      rq.Tags,
      COALESCE(am.AnswerCount, 0) AS TotalAnswers,
      COALESCE(am.TotalAnswerScore, 0) AS SumOfAnswerScores,
      COALESCE(am.AverageAnswerScore, 0) AS AvgAnswerScore,
      COALESCE(ca.CommentCount, 0) AS TotalComments,
      COALESCE(ca.UserCommentCount, 0) AS UserComments,
      COALESCE(ca.AnonymousCommentCount, 0) AS AnonymousComments,
      COALESCE(ca.AverageCommentScore, 0) AS AvgCommentScore,
      CASE WHEN p_closed.Id IS NOT NULL THEN p_closed.ClosedDate ELSE NULL END AS ClosedDate,
      CASE WHEN hr.Id IS NOT NULL THEN hr.DisplayName ELSE 'Non-Reputable' END AS OwnerReputationStatus,
      rq.HasAcceptedAnswer,
      ROW_NUMBER() OVER (ORDER BY rq.Score DESC, rq.CreationDate DESC) AS RowNum
    FROM
      RecentQuestions AS rq
      LEFT JOIN AnswerMetrics AS am ON rq.PostId = am.ParentId
      LEFT JOIN CommentAnalysis AS ca ON rq.PostId = ca.PostId
      LEFT JOIN Posts AS p_closed ON rq.PostId = p_closed.Id AND p_closed.ClosedDate IS NOT NULL
      LEFT JOIN HighReputationUsers AS hr ON rq.OwnerUserId = hr.Id
  )
SELECT
  pwj.PostId,
  pwj.Title,
  pwj.QuestionCreationDate,
  pwj.OwnerDisplayName,
  pwj.QuestionScore,
  pwj.QuestionAnswerCount,
  pwj.Tags,
  pwj.TotalAnswers,
  pwj.SumOfAnswerScores,
  pwj.AvgAnswerScore,
  pwj.TotalComments,
  pwj.UserComments,
  pwj.AnonymousComments,
  pwj.AvgCommentScore,
  pwj.ClosedDate,
  pwj.OwnerReputationStatus,
  CASE
    WHEN pwj.AvgAnswerScore > 10 AND pwj.TotalComments < 5 THEN 'High Answer Quality, Low Engagement'
    WHEN pwj.AvgAnswerScore < 0 AND pwj.TotalAnswers > 5 THEN 'Poor Answer Quality'
    WHEN pwj.TotalAnswers = 0 AND pwj.QuestionScore > 50 THEN 'Popular Question, No Answers Yet'
    ELSE 'Standard'
  END AS PerformanceCategory,
  SUBSTRING(pwj.Tags FROM 1 FOR (POSITION('><' IN pwj.Tags) - 1)) AS FirstTag,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = pwj.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  CASE WHEN pwj.HasAcceptedAnswer = 1 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswerString
FROM
  PostWithJoins AS pwj
WHERE
  pwj.RowNum <= 100
  AND (pwj.OwnerReputationStatus <> 'Non-Reputable' OR pwj.QuestionScore > 200)
UNION
SELECT
  NULL AS PostId,
  '--- Low Activity Posts ---' AS Title,
  NULL AS QuestionCreationDate,
  NULL AS OwnerDisplayName,
  NULL AS QuestionScore,
  NULL AS QuestionAnswerCount,
  NULL AS Tags,
  0 AS TotalAnswers,
  0 AS SumOfAnswerScores,
  0 AS AvgAnswerScore,
  0 AS TotalComments,
  0 AS UserComments,
  0 AS AnonymousComments,
  0 AS AvgCommentScore,
  NULL AS ClosedDate,
  'Low Activity' AS OwnerReputationStatus,
  NULL AS PerformanceCategory,
  NULL AS FirstTag,
  NULL AS DuplicateLinkCount,
  NULL AS HasAcceptedAnswerString
FROM
  (SELECT 1) AS dummy
WHERE
  NOT EXISTS (
    SELECT
      1
    FROM
      PostWithJoins AS pwj_low
    WHERE
      pwj_low.RowNum <= 100
      AND (pwj_low.OwnerReputationStatus <> 'Non-Reputable' OR pwj_low.QuestionScore > 200)
  )
UNION ALL
SELECT
  pwj.PostId,
  pwj.Title,
  pwj.QuestionCreationDate,
  pwj.OwnerDisplayName,
  pwj.QuestionScore,
  pwj.QuestionAnswerCount,
  pwj.Tags,
  pwj.TotalAnswers,
  pwj.SumOfAnswerScores,
  pwj.AvgAnswerScore,
  pwj.TotalComments,
  pwj.UserComments,
  pwj.AnonymousComments,
  pwj.AvgCommentScore,
  pwj.ClosedDate,
  pwj.OwnerReputationStatus,
  CASE
    WHEN pwj.AvgAnswerScore > 10 AND pwj.TotalComments < 5 THEN 'High Answer Quality, Low Engagement'
    WHEN pwj.AvgAnswerScore < 0 AND pwj.TotalAnswers > 5 THEN 'Poor Answer Quality'
    WHEN pwj.TotalAnswers = 0 AND pwj.QuestionScore > 50 THEN 'Popular Question, No Answers Yet'
    ELSE 'Standard'
  END AS PerformanceCategory,
  SUBSTRING(pwj.Tags FROM 1 FOR (POSITION('><' IN pwj.Tags) - 1)) AS FirstTag,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = pwj.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  CASE WHEN pwj.HasAcceptedAnswer = 1 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswerString
FROM
  PostWithJoins AS pwj
WHERE
  pwj.RowNum > 1000
ORDER BY
  PerformanceCategory,
  QuestionScore DESC;