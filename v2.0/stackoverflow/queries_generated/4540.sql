-- {"query": "4540.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1693} 

WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      u.DisplayName AS QuestionOwnerDisplayName,
      p.AnswerCount,
      p.Score AS QuestionScore,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      COALESCE(
        (
          SELECT
            MAX(CAST(ph.CreationDate AS DATE))
          FROM
            PostHistory ph
          WHERE
            ph.PostId = p.Id
            AND ph.PostHistoryTypeId IN (1, 4, 7)
        ),
        p.CreationDate
      ) AS LastTitleOrBodyEditDate,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      pt.Name = 'Question'
      AND p.AcceptedAnswerId IS NOT NULL
      AND p.ClosedDate IS NULL
      AND p.OwnerUserId IS NOT NULL
      AND p.Title IS NOT NULL
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.Score AS AnswerScore,
      a.CreationDate AS AnswerCreationDate,
      au.DisplayName AS AnswerOwnerDisplayName,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByAnswerScore
    FROM
      Posts a
      JOIN PostTypes pt ON a.PostTypeId = pt.Id
      LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE
      pt.Name = 'Answer'
      AND a.ParentId IS NOT NULL
      AND a.OwnerUserId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT ph.PostId) AS PostsEdited,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.PostId END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.PostId END) AS RawBodyEdits,
      MAX(ph.CreationDate) AS LastPostEditDate
    FROM
      PostHistory ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9)
    GROUP BY
      ph.UserId
    HAVING
      COUNT(DISTINCT ph.PostId) > 5
  ),
  TopQuestions AS (
    SELECT
      qs.QuestionId,
      qs.QuestionTitle,
      qs.QuestionOwnerDisplayName,
      qs.AnswerCount,
      qs.QuestionScore,
      qs.FavoriteCount,
      qs.QuestionViewCount,
      qs.LastTitleOrBodyEditDate,
      ad.AnswerId AS TopAnswerId,
      ad.AnswerScore AS TopAnswerScore,
      ad.AnswerOwnerDisplayName AS TopAnswerOwnerDisplayName,
      ad.AnswerCreationDate AS TopAnswerCreationDate,
      ue.UserId AS TopEditorId,
      ue.PostsEdited AS TopEditorPostsEdited,
      ue.BodyEdits AS TopEditorBodyEdits,
      ue.LastPostEditDate AS TopEditorLastPostEditDate
    FROM
      QuestionStats qs
      LEFT JOIN AnswerDetails ad
        ON qs.QuestionId = ad.QuestionId AND ad.RankByAnswerScore = 1
      LEFT JOIN PostHistory ph_edit ON qs.QuestionId = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (2, 5) -- Body edits
      LEFT JOIN UserEngagement ue ON ph_edit.UserId = ue.UserId AND ue.UserId = qs.OwnerUserId -- Self-edits
    WHERE
      qs.RankByScore <= 100
  )
SELECT
  tk.QuestionId,
  tk.QuestionTitle,
  tk.QuestionOwnerDisplayName,
  tk.AnswerCount,
  tk.QuestionScore,
  tk.FavoriteCount,
  tk.QuestionViewCount,
  tk.LastTitleOrBodyEditDate,
  tk.TopAnswerId,
  tk.TopAnswerScore,
  tk.TopAnswerOwnerDisplayName,
  tk.TopAnswerCreationDate,
  CASE
    WHEN tk.TopEditorId IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS HasTopEditorInvolved,
  ue_all.PostsEdited AS TotalPostsEditedByTopEditor,
  CASE
    WHEN tk.QuestionOwnerDisplayName = tk.TopAnswerOwnerDisplayName THEN 'Self-Answered'
    ELSE 'Not Self-Answered'
  END AS SelfAnswerStatus,
  CONCAT(
    tk.QuestionScore,
    '-',
    tk.FavoriteCount,
    '-',
    tk.QuestionViewCount
  ) AS ScoreFavoriteViewConcat,
  DATEDIFF(
    day,
    tk.QuestionCreationDate,
    tk.LastTitleOrBodyEditDate
  ) AS DaysSinceLastEdit,
  CASE
    WHEN tk.QuestionScore > 500 THEN 'High'
    WHEN tk.QuestionScore BETWEEN 100 AND 500 THEN 'Medium'
    ELSE 'Low'
  END AS ScoreCategory,
  IIF(
    tk.TopAnswerScore > 100,
    'Highly Rated Answer',
    'Standard Answer'
  ) AS AnswerRating,
  IIF(
    tk.TopEditorPostsEdited > 50,
    'Prolific Editor',
    'Moderate Editor'
  ) AS EditorProlificacy,
  COALESCE(
    tk.TopAnswerOwnerDisplayName,
    'No Answer Found'
  ) AS AnswerOwnerDisplay,
  UPPER(
    SUBSTRING(
      tk.QuestionTitle,
      1,
      CASE WHEN LEN(tk.QuestionTitle) > 10 THEN 10 ELSE LEN(tk.QuestionTitle) END
    )
  ) AS TruncatedTitleUpper,
  CASE
    WHEN tk.QuestionViewCount > 1000000 THEN 'Viral'
    WHEN tk.QuestionViewCount > 100000 THEN 'Popular'
    ELSE 'Standard'
  END AS ViewCountCategory,
  tk.QuestionScore + tk.FavoriteCount AS CombinedScoreFavorite,
  tk.QuestionScore * tk.AnswerCount AS ScoreByAnswerCount,
  tk.QuestionViewCount / NULLIF(tk.AnswerCount, 0) AS ViewsPerAnswer,
  tk.QuestionOwnerDisplayName LIKE '% a %' AS OwnerNameContainsA,
  (
    tk.QuestionScore % 7
  ) AS ScoreModulo7,
  tl.RankByScore AS QuestionRankOverall
FROM
  TopQuestions tk
  LEFT JOIN UserEngagement ue_all ON tk.TopEditorId = ue_all.UserId
  LEFT JOIN QuestionStats tl ON tk.QuestionId = tl.QuestionId
WHERE
  tk.QuestionScore > 0
  AND tk.AnswerCount > 0
  AND tk.TopAnswerScore > 0
  AND tk.QuestionViewCount IS NOT NULL
ORDER BY
  tk.QuestionScore DESC,
  tk.FavoriteCount DESC
LIMIT
  50;
