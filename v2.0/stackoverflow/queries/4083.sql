WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.Score AS QuestionScore,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
  ),
  QuestionAnswers AS (
    SELECT
      ans.ParentId AS QuestionId,
      COUNT(ans.Id) AS AnswerCountForQuestion,
      SUM(ans.Score) AS TotalAnswerScore,
      AVG(ans.Score) AS AverageAnswerScore,
      MAX(ans.CreationDate) AS LatestAnswerDate,
      COUNT(CASE WHEN ans.OwnerUserId = q.OwnerUserId THEN 1 END) AS AnswersFromOwner,
      COUNT(CASE WHEN ans.Id = q.AcceptedAnswerId THEN 1 END) AS IsAcceptedAnswerPresent
    FROM Posts AS ans
    JOIN Posts AS q
      ON ans.ParentId = q.Id
    WHERE
      ans.PostTypeId = 2
    GROUP BY
      ans.ParentId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS QuestionsAsked,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.PostId END) AS EditsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
      COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (2, 5)
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  QuestionAnalysis AS (
    SELECT
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionCreationDate,
      rq.AnswerCount AS BaseAnswerCount,
      COALESCE(qa.AnswerCountForQuestion, 0) AS ActualAnswerCount,
      COALESCE(qa.TotalAnswerScore, 0) AS TotalAnswerScore,
      COALESCE(qa.AverageAnswerScore, 0) AS AverageAnswerScore,
      COALESCE(qa.AnswersFromOwner, 0) AS AnswersFromOwner,
      CASE
        WHEN COALESCE(qa.IsAcceptedAnswerPresent, 0) > 0 THEN 'Accepted'
        ELSE 'Not Accepted'
      END AS AcceptanceStatus,
      EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rq.QuestionCreationDate)) / 3600.0 AS HoursSinceCreation,
      CASE
        WHEN rq.QuestionScore > 100 THEN 'HighScore'
        WHEN rq.QuestionScore > 10 THEN 'MediumScore'
        ELSE 'LowScore'
      END AS ScoreBracket,
      ua.Reputation AS OwnerReputation,
      ua.DisplayName AS OwnerDisplayName,
      CASE
        WHEN rq.QuestionCreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days') AND rq.AnswerCount = 0 THEN 'Unanswered_Old'
        WHEN rq.AnswerCount = 0 THEN 'Unanswered_Recent'
        ELSE 'Answered'
      END AS AnswerStatus,
      rq.rn
    FROM RecentQuestions AS rq
    LEFT JOIN QuestionAnswers AS qa
      ON rq.QuestionId = qa.QuestionId
    LEFT JOIN UserActivity AS ua
      ON rq.OwnerUserId = ua.UserId
    WHERE
      rq.rn <= 500
  )
SELECT
  qa.QuestionId,
  qa.QuestionTitle,
  qa.QuestionCreationDate,
  qa.BaseAnswerCount,
  qa.ActualAnswerCount,
  qa.TotalAnswerScore,
  qa.AverageAnswerScore,
  qa.AnswersFromOwner,
  qa.AcceptanceStatus,
  qa.HoursSinceCreation,
  qa.ScoreBracket,
  qa.OwnerReputation,
  qa.OwnerDisplayName,
  qa.AnswerStatus,
  CASE
    WHEN qa.OwnerReputation > 50000 AND qa.ActualAnswerCount > 10 THEN 'HighEngagement_HighRep'
    WHEN qa.OwnerReputation < 1000 AND qa.ActualAnswerCount = 0 THEN 'LowEngagement_LowRep_Unanswered'
    WHEN qa.HoursSinceCreation < 24 AND qa.ActualAnswerCount = 0 THEN 'Recent_Unanswered'
    ELSE 'Standard'
  END AS EngagementCategory,
  CASE WHEN qa.OwnerReputation IS NULL THEN 'UnknownOwner' ELSE 'KnownOwner' END AS OwnerStatus,
  LENGTH(qa.QuestionTitle) AS TitleLength,
  CASE
    WHEN qa.OwnerReputation < 1000 THEN 'Bronze'
    WHEN qa.OwnerReputation BETWEEN 1000 AND 10000 THEN 'Silver'
    WHEN qa.OwnerReputation > 10000 THEN 'Gold'
    ELSE 'NoReputation'
  END AS ReputationTier
FROM QuestionAnalysis AS qa
WHERE
  qa.OwnerReputation > 0
UNION ALL
SELECT
  NULL AS QuestionId,
  'Summary Stat' AS QuestionTitle,
  NULL AS QuestionCreationDate,
  AVG(BaseAnswerCount) AS BaseAnswerCount,
  AVG(ActualAnswerCount) AS ActualAnswerCount,
  SUM(TotalAnswerScore) AS TotalAnswerScore,
  AVG(AverageAnswerScore) AS AverageAnswerScore,
  SUM(AnswersFromOwner) AS AnswersFromOwner,
  'N/A' AS AcceptanceStatus,
  AVG(HoursSinceCreation) AS HoursSinceCreation,
  'N/A' AS ScoreBracket,
  AVG(OwnerReputation) AS OwnerReputation,
  'Overall' AS OwnerDisplayName,
  'N/A' AS AnswerStatus,
  'N/A' AS EngagementCategory,
  'N/A' AS OwnerStatus,
  AVG(LENGTH(QuestionTitle)) AS TitleLength,
  'N/A' AS ReputationTier
FROM QuestionAnalysis
WHERE
  QuestionId IS NOT NULL;