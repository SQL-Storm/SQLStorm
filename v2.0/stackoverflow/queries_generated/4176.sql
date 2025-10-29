-- {"query": "4176.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1263} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
      AND p.OwnerUserId IS NOT NULL
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      q.AnswerCount,
      q.Score AS QuestionScore,
      q.FavoriteCount,
      q.Tags,
      CASE
        WHEN q.AcceptedAnswerId IS NOT NULL THEN 1
        ELSE 0
      END AS HasAcceptedAnswer,
      DENSE_RANK() OVER (ORDER BY q.CreationDate DESC) AS QuestionRankByDate,
      ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionSequence
    FROM Posts AS q
    WHERE
      q.PostTypeId = 1 -- Questions
      AND q.OwnerUserId IS NOT NULL
      AND q.CreationDate > DATE('now', '-365 day')
  ),
  TopThreeAnswers AS (
    SELECT
      ra.QuestionId,
      COUNT(ra.PostId) AS NumTopThreeAnswers
    FROM RankedAnswers AS ra
    WHERE
      ra.rn <= 3
    GROUP BY
      ra.QuestionId
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS TotalAnswersPosted,
      AVG(p.Score) AS AvgAnswerScore,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 2
    GROUP BY
      u.Id
  ),
  UserQuestionStats AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS TotalQuestionsPosted,
      AVG(p.Score) AS AvgQuestionScore,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY
      u.Id
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionOwnerUserId,
  u.DisplayName AS QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.AnswerCount,
  qd.QuestionScore,
  qd.FavoriteCount,
  qd.HasAcceptedAnswer,
  qd.Tags,
  qd.QuestionRankByDate,
  qd.UserQuestionSequence,
  COALESCE(t3a.NumTopThreeAnswers, 0) AS NumTopThreeAnswers,
  uas.TotalAnswersPosted AS UserTotalAnswersPosted,
  uas.AvgAnswerScore AS UserAvgAnswerScore,
  uas.PositiveScoreAnswers AS UserPositiveScoreAnswers,
  uqs.TotalQuestionsPosted AS UserTotalQuestionsPosted,
  uqs.AvgQuestionScore AS UserAvgQuestionScore,
  uqs.PositiveScoreQuestions AS UserPositiveScoreQuestions,
  ph.PostHistoryCount,
  CASE
    WHEN qd.QuestionScore > 1000 AND qd.FavoriteCount > 50 THEN 'Highly Favored'
    WHEN qd.QuestionScore > 500 THEN 'Popular'
    WHEN qd.AnswerCount > 10 AND qd.HasAcceptedAnswer = 1 THEN 'Well-Answered'
    ELSE 'Standard'
  END AS QuestionCategorization,
  REPLACE(SUBSTRING(qd.Tags, 2, LENGTH(qd.Tags) - 2), '><', ' | ') AS FormattedTags,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = qd.QuestionId
      AND c.CreationDate > qd.QuestionCreationDate
      AND c.UserId IS NOT NULL
  ) AS CommentCountOnQuestionAfterCreation,
  CAST(JULIANDAY(qd.QuestionCreationDate) AS INTEGER) % 7 AS DayOfWeekQuestionCreated
FROM QuestionDetails AS qd
LEFT JOIN Users AS u
  ON qd.QuestionOwnerUserId = u.Id
LEFT JOIN TopThreeAnswers AS t3a
  ON qd.QuestionId = t3a.QuestionId
LEFT JOIN UserAnswerStats AS uas
  ON qd.QuestionOwnerUserId = uas.UserId
LEFT JOIN UserQuestionStats AS uqs
  ON qd.QuestionOwnerUserId = uqs.UserId
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS PostHistoryCount
  FROM PostHistory
  WHERE
    PostHistoryTypeId IN (1, 4, 6, 7) -- Title related changes
  GROUP BY
    PostId
) AS ph
  ON qd.QuestionId = ph.PostId
WHERE
  qd.QuestionScore > 0
  OR qd.AnswerCount > 0
ORDER BY
  qd.QuestionRankByDate,
  qd.QuestionScore DESC
LIMIT 1000;
