-- {"query": "4990.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1690}
WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.ViewCount AS NUMERIC)) AS AvgViewCount,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
    GROUP BY
      p.OwnerUserId
  ),
  TopUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      ups.TotalPosts,
      ups.TotalScore,
      ups.AvgViewCount,
      ups.LatestPostDate
    FROM
      Users u
      JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    WHERE
      u.Reputation > 10000
      AND ups.TotalPosts > 50
  ),
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.EditDate AS LastEditDate,
      u.DisplayName AS LastEditorDisplayName
    FROM
      RankedPostEdits rpe
      JOIN Users u ON rpe.UserId = u.Id
    WHERE
      rpe.rn = 1
  ),
  PostQuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.CreationDate AS QuestionCreationDate,
      COALESCE(u_q.DisplayName, p.OwnerDisplayName) AS QuestionOwnerDisplayName,
      COALESCE(le.LastEditorDisplayName, CAST('Community' AS VARCHAR)) AS QuestionLastEditorDisplayName,
      le.LastEditDate AS QuestionLastEditDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus
    FROM
      Posts p
      LEFT JOIN Users u_q ON p.OwnerUserId = u_q.Id
      LEFT JOIN LatestEdits le ON p.Id = le.PostId
    WHERE
      p.PostTypeId = 1
  ),
  AnswerQuality AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Id = a.ParentId /* placeholder, will be fixed below */ THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      AVG(CAST(a.Score AS NUMERIC)) AS AvgAnswerScore,
      MAX(a.CreationDate) AS LatestAnswerDate,
      SUM(CASE WHEN EXISTS (
            SELECT 1 FROM Comments c WHERE c.PostId = a.Id AND LENGTH(c.Text) > 200
          ) THEN 1 ELSE 0 END) AS AnswersWithLongComments
    FROM
      Posts a
    WHERE
      a.PostTypeId = 2
      AND a.ParentId IS NOT NULL
    GROUP BY
      a.ParentId
  )
SELECT
  pqd.QuestionId,
  pqd.Title,
  pqd.Tags,
  pqd.QuestionOwnerDisplayName,
  pqd.QuestionScore,
  pqd.QuestionViewCount,
  pqd.AnswerCount AS TotalAnswers,
  aq.AcceptedAnswerCount,
  aq.AvgAnswerScore,
  aq.LatestAnswerDate,
  aq.AnswersWithLongComments,
  pqd.FavoriteCount,
  pqd.CommentCount AS QuestionComments,
  pqd.QuestionCreationDate,
  pqd.QuestionLastEditorDisplayName,
  pqd.QuestionLastEditDate,
  pqd.QuestionStatus,
  u_top.DisplayName AS TopUserDisplayName,
  u_top.Reputation AS TopUserReputation,
  u_top.TotalPosts AS TopUserTotalPosts,
  u_top.TotalScore AS TopUserTotalScore,
  (
    SELECT
      COUNT(ph_close.Id)
    FROM
      PostHistory ph_close
    WHERE
      ph_close.PostId = pqd.QuestionId
      AND ph_close.PostHistoryTypeId = 10
      AND ph_close.Comment LIKE '%101%'
  ) AS CloseVotesForDuplicate,
  (pqd.QuestionScore * 1.0 / NULLIF(pqd.QuestionViewCount, 0)) AS ScorePerViewRatio,
  UPPER(SUBSTRING(pqd.Title FROM 1 FOR 3)) AS TitlePrefix,
  CASE
    WHEN pqd.QuestionCreationDate < cast('2024-10-01' as date) - INTERVAL '1 year' THEN 'Old'
    WHEN pqd.QuestionCreationDate < cast('2024-10-01' as date) - INTERVAL '3 month' THEN 'Medium'
    ELSE 'New'
  END AS QuestionAgeCategory,
  CASE
    WHEN pqd.AnswerCount > 5 AND aq.AvgAnswerScore > 10 THEN 'High Engagement & Quality'
    WHEN pqd.AnswerCount > 0 AND aq.AcceptedAnswerCount > 0 THEN 'Has Accepted Answer'
    WHEN pqd.AnswerCount = 0 THEN 'No Answers'
    ELSE 'Other Engagement'
  END AS EngagementCategory
FROM
  PostQuestionDetails pqd
  LEFT JOIN AnswerQuality aq ON pqd.QuestionId = aq.QuestionId
  LEFT JOIN TopUsers u_top ON pqd.QuestionOwnerDisplayName = u_top.DisplayName
WHERE
  (
    pqd.QuestionScore > 0
    AND pqd.QuestionViewCount > 100
    AND EXISTS (
      SELECT 1 FROM Tags t WHERE t.TagName = 'sql' AND pqd.Tags LIKE '%' || t.TagName || '%'
    )
  )
  OR pqd.QuestionStatus = 'Open'
GROUP BY
  pqd.QuestionId,
  pqd.Title,
  pqd.Tags,
  pqd.QuestionOwnerDisplayName,
  pqd.QuestionScore,
  pqd.QuestionViewCount,
  pqd.AnswerCount,
  aq.AcceptedAnswerCount,
  aq.AvgAnswerScore,
  aq.LatestAnswerDate,
  aq.AnswersWithLongComments,
  pqd.FavoriteCount,
  pqd.CommentCount,
  pqd.QuestionCreationDate,
  pqd.QuestionLastEditorDisplayName,
  pqd.QuestionLastEditDate,
  pqd.QuestionStatus,
  u_top.DisplayName,
  u_top.Reputation,
  u_top.TotalPosts,
  u_top.TotalScore
HAVING
  COUNT(pqd.QuestionId) > 0;