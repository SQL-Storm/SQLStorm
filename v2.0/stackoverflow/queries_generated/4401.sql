-- {"query": "4401.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1940} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId AS QuestionOwnerUserId,
      u.DisplayName AS QuestionOwnerDisplayName,
      u.Reputation AS QuestionOwnerReputation,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.ViewCount, 0) AS ViewCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed
    FROM
      Posts AS p
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions
  ),
  AnswerAggregates AS (
    SELECT
      ParentId AS QuestionId,
      COUNT(*) AS TotalAnswers,
      SUM(CASE WHEN p.Id = qd.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM
      Posts AS p
      LEFT JOIN QuestionDetails AS qd
        ON p.ParentId = qd.QuestionId
    WHERE
      p.PostTypeId = 2 -- Answers
    GROUP BY
      ParentId
  ),
  CommentStats AS (
    SELECT
      PostId,
      COUNT(*) AS CommentCount,
      SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
      AVG(c.Score) AS AverageCommentScore
    FROM
      Comments AS c
    GROUP BY
      PostId
  ),
  PostHistoryAggregates AS (
    SELECT
      PostId,
      COUNT(CASE WHEN PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
      COUNT(CASE WHEN PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN PostHistoryTypeId = 6 THEN 1 END) AS TagEdits,
      MAX(CreationDate) AS LastEditDate
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      PostId
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(*) AS UserPostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswerCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(p.CreationDate) AS LastPostCreationDate
    FROM
      Posts AS p
      LEFT JOIN Badges AS b
        ON p.OwnerUserId = b.UserId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId != -1
    GROUP BY
      UserId
  ),
  ComplexCalculations AS (
    SELECT
      qd.QuestionId,
      qd.QuestionTitle,
      qd.QuestionOwnerDisplayName,
      qd.QuestionOwnerReputation,
      qd.QuestionCreationDate,
      qd.IsClosed,
      COALESCE(aa.TotalAnswers, 0) AS TotalAnswers,
      CASE
        WHEN COALESCE(aa.IsAcceptedAnswerPresent, 0) = 1 THEN 'Accepted Answer Exists'
        ELSE 'No Accepted Answer Yet'
      END AS AnswerStatus,
      COALESCE(cs.CommentCount, 0) AS TotalComments,
      CASE
        WHEN cs.AverageCommentScore > 5 THEN 'High Engagement'
        WHEN cs.AverageCommentScore > 0 THEN 'Moderate Engagement'
        ELSE 'Low Engagement'
      END AS CommentEngagement,
      COALESCE(pha.TitleEdits, 0) AS TitleEditCount,
      COALESCE(pha.BodyEdits, 0) AS BodyEditCount,
      COALESCE(pha.TagEdits, 0) AS TagEditCount,
      pha.LastEditDate,
      ua.UserPostCount,
      ua.UserQuestionCount,
      ua.UserAnswerCount,
      ua.BadgeCount,
      ua.LastPostCreationDate,
      DATEDIFF(day, qd.QuestionCreationDate, qd.ClosedDate) AS DaysToClose,
      qsu.DisplayName AS LastEditorDisplayName,
      ROUND(
        CAST(qd.ViewCount AS NUMERIC) / NULLIF(qd.AnswerCount, 0),
        2
      ) AS ViewsPerAnswer,
      LOWER(
        SUBSTRING(qd.QuestionTitle FROM 1 FOR 3) || '...' || SUBSTRING(qd.QuestionTitle FROM LENGTH(qd.QuestionTitle) - 2 FOR 3)
      ) AS TitleAbbreviation,
      CASE
        WHEN qd.QuestionOwnerReputation > 100000 THEN 'Guru'
        WHEN qd.QuestionOwnerReputation > 50000 THEN 'Expert'
        WHEN qd.QuestionOwnerReputation > 10000 THEN 'Advanced'
        WHEN qd.QuestionOwnerReputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
      END AS ReputationLevel
    FROM
      QuestionDetails AS qd
      LEFT JOIN AnswerAggregates AS aa
        ON qd.QuestionId = aa.QuestionId
      LEFT JOIN CommentStats AS cs
        ON qd.QuestionId = cs.PostId
      LEFT JOIN PostHistoryAggregates AS pha
        ON qd.QuestionId = pha.PostId
      LEFT JOIN UserActivity AS ua
        ON qd.QuestionOwnerUserId = ua.UserId
      LEFT JOIN Users AS qsu
        ON qd.QuestionOwnerUserId = qsu.Id
  )
SELECT
  cc.QuestionId,
  cc.QuestionTitle,
  cc.QuestionOwnerDisplayName,
  cc.QuestionOwnerReputation,
  cc.ReputationLevel,
  cc.QuestionCreationDate,
  cc.IsClosed,
  cc.DaysToClose,
  cc.TotalAnswers,
  cc.AnswerStatus,
  cc.TotalComments,
  cc.CommentEngagement,
  cc.TitleEditCount,
  cc.BodyEditCount,
  cc.TagEditCount,
  cc.LastEditDate,
  cc.UserPostCount,
  cc.UserQuestionCount,
  cc.UserAnswerCount,
  cc.BadgeCount,
  cc.LastPostCreationDate,
  cc.ViewsPerAnswer,
  cc.TitleAbbreviation,
  cc.FavoriteCount,
  cc.ViewCount,
  cc.LastEditorDisplayName,
  'Performance_Test_Result' AS BenchmarkTag
FROM
  ComplexCalculations AS cc
WHERE
  cc.QuestionOwnerReputation > 500 -- Filter for users with some reputation
  AND cc.TotalAnswers >= 2 -- Questions with at least two answers
  AND cc.BodyEditCount > 0 -- Questions that have been edited at least once
  AND cc.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Filter by creation date range
UNION
SELECT
  cc.QuestionId,
  cc.QuestionTitle,
  cc.QuestionOwnerDisplayName,
  cc.QuestionOwnerReputation,
  cc.ReputationLevel,
  cc.QuestionCreationDate,
  cc.IsClosed,
  cc.DaysToClose,
  cc.TotalAnswers,
  cc.AnswerStatus,
  cc.TotalComments,
  cc.CommentEngagement,
  cc.TitleEditCount,
  cc.BodyEditCount,
  cc.TagEditCount,
  cc.LastEditDate,
  cc.UserPostCount,
  cc.UserQuestionCount,
  cc.UserAnswerCount,
  cc.BadgeCount,
  cc.LastPostCreationDate,
  cc.ViewsPerAnswer,
  cc.TitleAbbreviation,
  cc.FavoriteCount,
  cc.ViewCount,
  cc.LastEditorDisplayName,
  'Performance_Test_Result' AS BenchmarkTag
FROM
  ComplexCalculations AS cc
WHERE
  cc.IsClosed = 1
  AND cc.DaysToClose < 30
  AND cc.FavoriteCount > 10
ORDER BY
  cc.QuestionCreationDate DESC,
  cc.QuestionOwnerReputation DESC;
