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
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM
      Posts p
      LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  ),
  AnswerAggregates AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(*) AS TotalAnswers,
      SUM(CASE WHEN p.Id = qd.QuestionId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM
      Posts p
      LEFT JOIN QuestionDetails qd
        ON p.ParentId = qd.QuestionId
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  CommentStats AS (
    SELECT
      c.PostId,
      COUNT(*) AS CommentCount,
      SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
      AVG(c.Score) AS AverageCommentScore
    FROM
      Comments c
    GROUP BY
      c.PostId
  ),
  PostHistoryAggregates AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 END) AS TagEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY
      ph.PostId
  ),
  UserActivity AS (
    SELECT
      p.OwnerUserId AS UserId,
      COUNT(*) AS UserPostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswerCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(p.CreationDate) AS LastPostCreationDate
    FROM
      Posts p
      LEFT JOIN Badges b
        ON p.OwnerUserId = b.UserId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
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
      CASE WHEN COALESCE(aa.IsAcceptedAnswerPresent, 0) = 1 THEN 'Accepted Answer Exists' ELSE 'No Accepted Answer Yet' END AS AnswerStatus,
      COALESCE(cs.CommentCount, 0) AS TotalComments,
      CASE
        WHEN COALESCE(cs.AverageCommentScore, 0) > 5 THEN 'High Engagement'
        WHEN COALESCE(cs.AverageCommentScore, 0) > 0 THEN 'Moderate Engagement'
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
      CASE WHEN qd.ClosedDate IS NOT NULL THEN EXTRACT(day FROM (CAST(qd.ClosedDate AS TIMESTAMP) - CAST(qd.QuestionCreationDate AS TIMESTAMP))) ELSE NULL END AS DaysToClose,
      qsu.DisplayName AS LastEditorDisplayName,
      ROUND(
        CASE WHEN qd.AnswerCount = 0 THEN NULL ELSE CAST(CAST(qd.ViewCount AS DECIMAL) / NULLIF(qd.AnswerCount,0) AS NUMERIC) END, 2
      ) AS ViewsPerAnswer,
      LOWER(
        SUBSTRING(qd.QuestionTitle FROM 1 FOR 3) || '...' || SUBSTRING(qd.QuestionTitle FROM (CHAR_LENGTH(qd.QuestionTitle) - 2) FOR 3)
      ) AS TitleAbbreviation,
      CASE
        WHEN qd.QuestionOwnerReputation > 100000 THEN 'Guru'
        WHEN qd.QuestionOwnerReputation > 50000 THEN 'Expert'
        WHEN qd.QuestionOwnerReputation > 10000 THEN 'Advanced'
        WHEN qd.QuestionOwnerReputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
      END AS ReputationLevel,
      qd.FavoriteCount,
      qd.ViewCount
    FROM
      QuestionDetails qd
      LEFT JOIN AnswerAggregates aa
        ON qd.QuestionId = aa.QuestionId
      LEFT JOIN CommentStats cs
        ON qd.QuestionId = cs.PostId
      LEFT JOIN PostHistoryAggregates pha
        ON qd.QuestionId = pha.PostId
      LEFT JOIN UserActivity ua
        ON qd.QuestionOwnerUserId = ua.UserId
      LEFT JOIN Users qsu
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
  ComplexCalculations cc
WHERE
  cc.QuestionOwnerReputation > 500
  AND cc.TotalAnswers >= 2
  AND cc.BodyEditCount > 0
  AND cc.QuestionCreationDate BETWEEN TIMESTAMP '2020-01-01' AND TIMESTAMP '2023-12-31'
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
  ComplexCalculations cc
WHERE
  cc.IsClosed = 1
  AND cc.DaysToClose < 30
  AND cc.FavoriteCount > 10
ORDER BY
  QuestionCreationDate DESC,
  QuestionOwnerReputation DESC;