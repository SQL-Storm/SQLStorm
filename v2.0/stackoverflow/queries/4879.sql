WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.Tags,
      u.DisplayName AS OwnerDisplayName,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days')
  ),
  QuestionAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCount,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(p.Score) AS AverageAnswerScore,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS TotalQuestionsAsked,
      COUNT(DISTINCT a.AnswerId) AS TotalAnswersGiven,
      SUM(CASE WHEN p.AcceptedAnswerId = a.AnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN (
      SELECT
        Id AS AnswerId,
        ParentId AS QuestionId
      FROM Posts
      WHERE
        PostTypeId = 2
    ) AS a
      ON p.Id = a.QuestionId
    GROUP BY
      u.Id
  ),
  TagWisdom AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS NumberOfQuestions,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AverageQuestionScore,
      MAX(p.ViewCount) AS MaxQuestionViews
    FROM Tags AS t
    JOIN Posts AS p
      ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY
      t.TagName
    HAVING
      COUNT(DISTINCT p.Id) > 50
  ),
  TopUsersByReputation AS (
    SELECT
      Id AS UserId,
      DisplayName,
      Reputation,
      Views,
      UpVotes,
      DownVotes,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE
      CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '730 days')
  )
SELECT
  rq.Title AS QuestionTitle,
  rq.OwnerDisplayName,
  rq.QuestionScore,
  rq.FavoriteCount,
  rq.AnswerCount AS RecentQuestionAnswerCount,
  COALESCE(qa.AnswerCount, 0) AS TotalAnswersForQuestion,
  COALESCE(qa.AverageAnswerScore, 0) AS AvgAnswerScoreForQuestion,
  COALESCE(uas.TotalQuestionsAsked, 0) AS UserTotalQuestions,
  COALESCE(uas.TotalAnswersGiven, 0) AS UserTotalAnswers,
  COALESCE(uas.AcceptedAnswers, 0) AS UserAcceptedAnswers,
  tw.TagName,
  tw.NumberOfQuestions AS TagQuestions,
  tw.AverageQuestionScore AS TagAvgScore,
  tur.DisplayName AS TopUserDisplayName,
  tur.Reputation AS TopUserReputation,
  tur.ReputationRank AS TopUserReputationRank,
  CASE
    WHEN rq.QuestionViewCount > 10000 THEN 'High Traffic'
    WHEN rq.QuestionViewCount > 1000 THEN 'Medium Traffic'
    ELSE 'Low Traffic'
  END AS TrafficCategory,
  UPPER(SUBSTRING(rq.Tags FROM 2 FOR (POSITION('>' IN rq.Tags) - 2))) AS PrimaryTag,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate'
    ELSE 'Not a Duplicate'
  END AS DuplicateStatus,
  ABS(
    (EXTRACT(EPOCH FROM rq.QuestionCreationDate) / 86400.0)
    - (EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') / 86400.0)
  ) AS DaysSinceCreation,
  rq.QuestionId,
  rq.OwnerUserId,
  rq.QuestionCreationDate,
  rq.QuestionViewCount,
  rq.Tags
FROM RecentQuestions AS rq
LEFT JOIN QuestionAnswers AS qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN UserAnswerStats AS uas
  ON rq.OwnerUserId = uas.UserId
LEFT JOIN TagWisdom AS tw
  ON rq.Tags LIKE '%' || tw.TagName || '%'
LEFT JOIN TopUsersByReputation AS tur
  ON rq.OwnerUserId = tur.UserId
WHERE
  rq.RowNum <= 10 AND tw.TagName IS NOT NULL AND tur.ReputationRank <= 100
UNION ALL
SELECT
  NULL AS QuestionTitle,
  NULL AS OwnerDisplayName,
  NULL AS QuestionScore,
  NULL AS FavoriteCount,
  NULL AS RecentQuestionAnswerCount,
  NULL AS TotalAnswersForQuestion,
  NULL AS AvgAnswerScoreForQuestion,
  NULL AS UserTotalQuestions,
  NULL AS UserTotalAnswers,
  NULL AS UserAcceptedAnswers,
  tw.TagName,
  tw.NumberOfQuestions AS TagQuestions,
  tw.AverageQuestionScore AS TagAvgScore,
  tur.DisplayName AS TopUserDisplayName,
  tur.Reputation AS TopUserReputation,
  tur.ReputationRank AS TopUserReputationRank,
  NULL AS TrafficCategory,
  UPPER(tw.TagName) AS PrimaryTag,
  NULL AS DuplicateStatus,
  NULL AS DaysSinceCreation,
  NULL AS QuestionId,
  NULL AS OwnerUserId,
  NULL AS QuestionCreationDate,
  NULL AS QuestionViewCount,
  NULL AS Tags
FROM TagWisdom AS tw
CROSS JOIN TopUsersByReputation AS tur
WHERE
  tw.TagName NOT IN (SELECT TagName FROM TagWisdom WHERE NumberOfQuestions > 500)
  AND tur.ReputationRank BETWEEN 50 AND 150;