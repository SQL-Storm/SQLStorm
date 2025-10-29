-- {"query": "4154.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2444} 

WITH
  AnsweredQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.FavoriteCount AS QuestionFavoriteCount,
      p.AnswerCount AS QuestionAnswerCount,
      COUNT(a.Id) AS ActualAnswerCount,
      MAX(a.Score) AS MaxAnswerScore,
      AVG(a.Score) AS AvgAnswerScore,
      SUM(CASE WHEN a.OwnerUserId = p.OwnerUserId THEN 1 ELSE 0 END) AS AnswersByQuestionOwner,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts AS p
    JOIN Posts AS a
      ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.FavoriteCount,
      p.AnswerCount
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
      COUNT(DISTINCT c.Id) AS CommentsMade,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  ),
  TopAnswers AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.Score AS AnswerScore,
      a.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts AS a
    WHERE
      a.PostTypeId = 2
  ),
  QuestionMetrics AS (
    SELECT
      aq.QuestionId,
      aq.QuestionTitle,
      aq.QuestionScore,
      aq.QuestionFavoriteCount,
      aq.QuestionAnswerCount,
      aq.ActualAnswerCount,
      aq.MaxAnswerScore,
      aq.AvgAnswerScore,
      aq.AnswersByQuestionOwner,
      aq.LastAnswerDate,
      ta.AnswerId AS TopAnswerId,
      ta.AnswerOwnerUserId AS TopAnswerOwnerUserId,
      ta.AnswerScore AS TopAnswerScore,
      ta.AnswerCreationDate AS TopAnswerCreationDate,
      CASE
        WHEN aq.QuestionOwnerUserId IS NULL THEN 'Anonymous'
        ELSE COALESCE(ua_q.DisplayName, 'Deleted User')
      END AS QuestionOwnerDisplayName,
      CASE
        WHEN ta.AnswerOwnerUserId IS NULL THEN 'Anonymous'
        ELSE COALESCE(ua_a.DisplayName, 'Deleted User')
      END AS TopAnswerOwnerDisplayName,
      DATEDIFF(
        day,
        aq.QuestionCreationDate,
        aq.LastAnswerDate
      ) AS DaysToFirstAnswer,
      ROW_NUMBER() OVER (ORDER BY aq.QuestionScore DESC, aq.QuestionFavoriteCount DESC) AS QuestionRank
    FROM AnsweredQuestions AS aq
    LEFT JOIN TopAnswers AS ta
      ON aq.QuestionId = ta.QuestionId AND ta.rn = 1
    LEFT JOIN UserActivity AS ua_q
      ON aq.QuestionOwnerUserId = ua_q.UserId
    LEFT JOIN UserActivity AS ua_a
      ON ta.AnswerOwnerUserId = ua_a.UserId
  )
SELECT
  qm.QuestionId,
  qm.QuestionTitle,
  qm.QuestionScore,
  qm.QuestionFavoriteCount,
  qm.QuestionAnswerCount,
  qm.ActualAnswerCount,
  qm.MaxAnswerScore,
  qm.AvgAnswerScore,
  qm.AnswersByQuestionOwner,
  qm.QuestionOwnerDisplayName,
  qm.TopAnswerId,
  qm.TopAnswerScore,
  qm.TopAnswerOwnerDisplayName,
  qm.DaysToFirstAnswer,
  ua.UserCreationDate,
  ua.Reputation,
  ua.UserViews,
  ua.UserUpVotes,
  ua.UserDownVotes,
  ua.QuestionsAsked,
  ua.AnswersGiven,
  ua.CommentsMade,
  ua.BadgesEarned,
  ua.TotalAnswerScore,
  CASE
    WHEN ua.LastPostActivityDate IS NULL THEN 'Never'
    ELSE CAST(ua_m.LastPostActivityDate AS VARCHAR)
  END AS LastActivity,
  qm.QuestionRank,
  CASE
    WHEN qm.QuestionScore > 100 AND qm.ActualAnswerCount > 10 THEN 'High Impact'
    WHEN qm.QuestionScore < 0 AND qm.ActualAnswerCount < 3 THEN 'Low Engagement'
    ELSE 'Standard'
  END AS QuestionImpactCategory,
  '---' AS Separator,
  (
    SELECT
      COUNT(*)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = qm.QuestionId AND ph.PostHistoryTypeId IN (4, 5)
  ) AS EditCountForQuestion,
  (
    SELECT
      SUM(ph_inner.Text::INT) -- Assuming Text column stores integer votes for deletion/undeletion
    FROM PostHistory AS ph_inner
    WHERE
      ph_inner.PostId = qm.QuestionId AND ph_inner.PostHistoryTypeId IN (12, 13)
  ) AS VoteCountForQuestionHistory,
  COALESCE(pt.Name, 'Unknown Post Type') AS QuestionPostTypeName,
  CASE
    WHEN qm.QuestionScore < 0 THEN 'Negative Score'
    WHEN qm.QuestionScore BETWEEN 0 AND 10 THEN 'Low Score'
    WHEN qm.QuestionScore BETWEEN 11 AND 50 THEN 'Medium Score'
    ELSE 'High Score'
  END AS ScoreCategory,
  UPPER(SUBSTRING(qm.QuestionTitle, 1, 3)) AS TitlePrefix,
  JSON_ARRAY_LENGTH(
    CASE
      WHEN qm.QuestionTitle LIKE '%[%]%' THEN REPLACE(REPLACE(qm.QuestionTitle, '[', '["'), ']', '"]')
      ELSE '[]'
    END
  ) AS TagCountInTitle,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Link'
    ELSE 'Not a Duplicate Link'
  END AS LinkStatus,
  CASE
    WHEN qm.QuestionScore IS NULL THEN 'NULL Score'
    WHEN qm.QuestionFavoriteCount IS NULL THEN 'NULL FavoriteCount'
    ELSE 'Valid'
  END AS DataValidity,
  LAG(qm.QuestionScore, 1, 0) OVER (ORDER BY qm.QuestionCreationDate) AS PreviousQuestionScore,
  LEAD(qm.QuestionScore, 1, 0) OVER (ORDER BY qm.QuestionCreationDate) AS NextQuestionScore,
  qm.QuestionRank - ROW_NUMBER() OVER (PARTITION BY qm.QuestionOwnerDisplayName ORDER BY qm.QuestionScore DESC) AS RankDifferenceForOwner,
  ua_m.UserCreationDate AS ModeratorOrAdminCreationDate,
  CASE
    WHEN qm.QuestionOwnerDisplayName = 'Anonymous' OR qm.QuestionOwnerDisplayName IS NULL THEN 1
    ELSE 0
  END AS IsQuestionAnonymousOrDeleted
FROM QuestionMetrics AS qm
LEFT JOIN UserActivity AS ua
  ON qm.QuestionOwnerUserId = ua.UserId
LEFT JOIN UserActivity AS ua_m
  ON qm.TopAnswerOwnerUserId = ua_m.UserId -- Joining for moderator/admin activity if applicable
LEFT JOIN PostTypes AS pt
  ON 1 = pt.Id -- Hardcoded for Question PostType
WHERE
  qm.QuestionScore > -5 AND qm.ActualAnswerCount > 0
UNION
SELECT
  NULL AS QuestionId,
  NULL AS QuestionTitle,
  NULL AS QuestionScore,
  NULL AS QuestionFavoriteCount,
  NULL AS QuestionAnswerCount,
  NULL AS ActualAnswerCount,
  NULL AS MaxAnswerScore,
  NULL AS AvgAnswerScore,
  NULL AS AnswersByQuestionOwner,
  NULL AS QuestionOwnerDisplayName,
  NULL AS TopAnswerId,
  NULL AS TopAnswerScore,
  NULL AS TopAnswerOwnerDisplayName,
  NULL AS DaysToFirstAnswer,
  ua.UserCreationDate,
  ua.Reputation,
  ua.UserViews,
  ua.UserUpVotes,
  ua.UserDownVotes,
  ua.QuestionsAsked,
  ua.AnswersGiven,
  ua.CommentsMade,
  ua.BadgesEarned,
  ua.TotalAnswerScore,
  CAST(ua.LastPostActivityDate AS VARCHAR) AS LastActivity,
  NULL AS QuestionRank,
  'User Summary' AS QuestionImpactCategory,
  '---' AS Separator,
  NULL AS EditCountForQuestion,
  NULL AS VoteCountForQuestionHistory,
  'User Stats' AS QuestionPostTypeName,
  NULL AS ScoreCategory,
  NULL AS TitlePrefix,
  NULL AS TagCountInTitle,
  NULL AS LinkStatus,
  NULL AS DataValidity,
  NULL AS PreviousQuestionScore,
  NULL AS NextQuestionScore,
  NULL AS RankDifferenceForOwner,
  NULL AS ModeratorOrAdminCreationDate,
  NULL AS IsQuestionAnonymousOrDeleted
FROM UserActivity AS ua
WHERE
  ua.Reputation > 10000
ORDER BY
  QuestionRank NULLS LAST,
  LastActivity DESC;
