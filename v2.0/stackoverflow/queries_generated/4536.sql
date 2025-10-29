-- {"query": "4536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1657} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 AND p.ParentId IS NOT NULL
  ),
  TopAnswers AS (
    SELECT
      PostId,
      QuestionId,
      Rank
    FROM RankedAnswers
    WHERE
      Rank <= 3
  ),
  QuestionsWithTopAnswers AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.OwnerUserId AS QuestionOwnerId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      ta.PostId AS TopAnswerId,
      ta.Rank AS AnswerRank
    FROM Posts AS q
    JOIN TopAnswers AS ta
      ON q.Id = ta.QuestionId
    WHERE
      q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE NULL END) AS EditedPostsCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE NULL END) AS ModerationActionsCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
      COUNT(DISTINCT c.Id) AS CommentCount,
      MAX(u.Reputation) AS MaxUserReputation
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagEngagement AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS PostsWithTag,
      SUM(p.Score) AS TotalScoreForTag
    FROM Tags AS t
    JOIN Posts AS p
      ON ',' + p.Tags + ',' LIKE '%,' + t.TagName + ',%'
    WHERE
      p.PostTypeId = 1 AND p.CreationDate BETWEEN DATEADD(year, -1, GETDATE()) AND GETDATE()
    GROUP BY
      t.TagName
    HAVING
      COUNT(DISTINCT p.Id) > 100
  )
SELECT
  qta.QuestionId,
  qta.QuestionTitle,
  qta.QuestionOwnerId,
  u.UserDisplayName AS QuestionOwnerDisplayName,
  qta.QuestionCreationDate,
  qta.QuestionScore,
  qta.QuestionViewCount,
  qta.TopAnswerId,
  ta.Score AS TopAnswerScore,
  ta.CreationDate AS TopAnswerCreationDate,
  qta.AnswerRank,
  ua.UserDisplayName AS TopAnswerOwnerDisplayName,
  ua.EditedPostsCount,
  ua.ModerationActionsCount,
  ua.UpVotesReceived AS TopAnswerOwnerUpVotes,
  ua.DownVotesReceived AS TopAnswerOwnerDownVotes,
  ua.CommentCount AS TopAnswerOwnerCommentCount,
  tu.TagName AS PrimaryTag,
  te.PostsWithTag AS PrimaryTagPostCount,
  te.TotalScoreForTag AS PrimaryTagTotalScore,
  IIF(qta.QuestionScore > 100 AND qta.QuestionViewCount > 10000, 'HighPerformance', 'Standard') AS PerformanceCategory,
  CASE
    WHEN qta.QuestionScore < 0 THEN 'NegativeScore'
    WHEN qta.QuestionScore BETWEEN 0 AND 50 THEN 'LowScore'
    WHEN qta.QuestionScore > 50 THEN 'HighScore'
    ELSE 'NoScore'
  END AS ScoreCategory,
  SUBSTRING(qta.QuestionTitle, 1, 10) AS TitlePrefix,
  UPPER(REPLACE(REPLACE(qta.QuestionTitle, '?', ''), '!', '')) AS CleanedTitle,
  COALESCE(qta.QuestionOwnerDisplayName, 'Community') AS OwnerDisplayNameFallback,
  CASE
    WHEN ta.Score IS NULL THEN 'No Answer'
    WHEN ta.Score >= 0 THEN 'PositiveOrZeroScore'
    WHEN ta.Score < 0 THEN 'NegativeScore'
  END AS TopAnswerScoreStatus
FROM QuestionsWithTopAnswers AS qta
LEFT JOIN Posts AS ta
  ON qta.TopAnswerId = ta.Id
LEFT JOIN Users AS u
  ON qta.QuestionOwnerId = u.Id
LEFT JOIN Users AS ua
  ON ta.OwnerUserId = ua.Id
LEFT JOIN UserActivity AS ua_activity
  ON ta.OwnerUserId = ua_activity.UserId
LEFT JOIN TagEngagement AS te
  ON SUBSTRING(qta.QuestionTitle, CHARINDEX('#', qta.QuestionTitle) + 1, CHARINDEX(' ', qta.QuestionTitle, CHARINDEX('#', qta.QuestionTitle)) - CHARINDEX('#', qta.QuestionTitle) - 1) = te.TagName -- Assuming tag is after # and before space in title for demonstration
LEFT JOIN Tags AS tu
  ON tu.TagName = SUBSTRING(qta.QuestionTitle, CHARINDEX('#', qta.QuestionTitle) + 1, CHARINDEX(' ', qta.QuestionTitle, CHARINDEX('#', qta.QuestionTitle)) - CHARINDEX('#', qta.QuestionTitle) - 1)
WHERE
  qta.QuestionCreationDate BETWEEN DATEADD(month, -6, GETDATE()) AND GETDATE()
  AND qta.QuestionScore > -5
UNION
SELECT
  NULL AS QuestionId,
  'Summary' AS QuestionTitle,
  NULL AS QuestionOwnerId,
  NULL AS QuestionOwnerDisplayName,
  NULL AS QuestionCreationDate,
  NULL AS QuestionScore,
  NULL AS QuestionViewCount,
  NULL AS TopAnswerId,
  NULL AS TopAnswerScore,
  NULL AS TopAnswerCreationDate,
  NULL AS AnswerRank,
  NULL AS TopAnswerOwnerDisplayName,
  AVG(ua.EditedPostsCount) AS EditedPostsCount,
  AVG(ua.ModerationActionsCount) AS ModerationActionsCount,
  AVG(ua.UpVotesReceived) AS TopAnswerOwnerUpVotes,
  AVG(ua.DownVotesReceived) AS TopAnswerOwnerDownVotes,
  AVG(ua.CommentCount) AS TopAnswerOwnerCommentCount,
  'Overall' AS PrimaryTag,
  NULL AS PrimaryTagPostCount,
  NULL AS PrimaryTagTotalScore,
  'Summary' AS PerformanceCategory,
  NULL AS ScoreCategory,
  NULL AS TitlePrefix,
  NULL AS CleanedTitle,
  NULL AS OwnerDisplayNameFallback,
  NULL AS TopAnswerScoreStatus
FROM UserActivity AS ua;
