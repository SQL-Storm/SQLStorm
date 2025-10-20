WITH QuestionAnswers AS (
  SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.OwnerUserId AS QuestionOwnerUserId,
    p.CreationDate AS QuestionCreationDate,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    SUM(a.Score) AS TotalAnswerScore,
    AVG(a.Score) AS AverageAnswerScore,
    MAX(a.CreationDate) AS LastAnswerDate,
    MIN(a.CreationDate) AS FirstAnswerDate,
    COUNT(DISTINCT c.Id) AS CommentCountOnQuestionAndAnswers,
    SUM(CASE WHEN a.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount
  FROM Posts AS p
  LEFT JOIN Posts AS a
    ON p.Id = a.ParentId AND a.PostTypeId = 2
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId OR a.Id = c.PostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate
), UserQuestionStats AS (
  SELECT
    qa.QuestionOwnerUserId AS UserId,
    COUNT(DISTINCT qa.QuestionId) AS TotalQuestionsAnswered,
    SUM(qa.TotalAnswerScore) AS TotalScoreFromAnswers,
    AVG(qa.AverageAnswerScore) AS AverageScoreOfAnswers,
    SUM(qa.AcceptedAnswerCount) AS TotalAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN qa.QuestionOwnerUserId = qa.QuestionOwnerUserId THEN qa.QuestionId ELSE NULL END) AS QuestionsTheyAnsweredForThemselves,
    MAX(qa.QuestionCreationDate) AS LatestQuestionAnsweredDate
  FROM QuestionAnswers AS qa
  GROUP BY
    qa.QuestionOwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccessDate,
  u.Views AS UserViews,
  u.UpVotes AS UserUpVotes,
  u.DownVotes AS UserDownVotes,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
  COALESCE(uq.TotalQuestionsAnswered, 0) AS TotalQuestionsAnswered,
  COALESCE(uq.TotalScoreFromAnswers, 0) AS TotalScoreFromAnswers,
  COALESCE(uq.AverageScoreOfAnswers, 0.0) AS AverageScoreOfAnswers,
  COALESCE(uq.TotalAcceptedAnswers, 0) AS TotalAcceptedAnswers,
  COALESCE(uq.QuestionsTheyAnsweredForThemselves, 0) AS QuestionsTheyAnsweredForThemselves,
  COALESCE(uq.LatestQuestionAnsweredDate, u.CreationDate) AS LatestActivityDate,
  COALESCE(SUM(CASE WHEN qa.CommentCountOnQuestionAndAnswers > 0 THEN 1 ELSE 0 END), 0) AS UsersWhoCommentedOnTheirAnswersOrQuestions
FROM Users AS u
LEFT JOIN Badges AS b
  ON u.Id = b.UserId
LEFT JOIN UserQuestionStats AS uq
  ON u.Id = uq.UserId
LEFT JOIN QuestionAnswers AS qa
  ON u.Id = qa.QuestionOwnerUserId
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  uq.TotalQuestionsAnswered,
  uq.TotalScoreFromAnswers,
  uq.AverageScoreOfAnswers,
  uq.TotalAcceptedAnswers,
  uq.QuestionsTheyAnsweredForThemselves,
  uq.LatestQuestionAnsweredDate
ORDER BY
  u.Reputation DESC,
  LatestActivityDate DESC
LIMIT 1000;