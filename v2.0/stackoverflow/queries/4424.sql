-- {"query": "4424.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 750}
WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId, PostHistoryTypeId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5) AND UserId IS NOT NULL
  ),
  LatestEdits AS (
    SELECT
      rph.PostId,
      u.DisplayName AS LastEditorDisplayName,
      rph.CreationDate AS LastEditDate,
      p.Title AS OriginalTitle,
      p.Tags AS OriginalTags,
      CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END AS AnswerCount
    FROM RankedPostHistory AS rph
    JOIN Users AS u
      ON rph.UserId = u.Id
    JOIN Posts AS p
      ON rph.PostId = p.Id
    WHERE
      rph.rn = 1
  ),
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  -- derive editor user id for each LatestEdits row by joining PostHistoryTypes and PostHistory
  EditUsers AS (
    SELECT
      le.PostId,
      le.LastEditorDisplayName,
      le.LastEditDate,
      le.OriginalTitle,
      le.OriginalTags,
      le.AnswerCount,
      ph.UserId AS EditorUserId
    FROM LatestEdits le
    LEFT JOIN PostHistoryTypes pht
      ON pht.Name = 'Edit Body'
    LEFT JOIN PostHistory ph
      ON ph.PostId = le.PostId
      AND ph.PostHistoryTypeId = pht.Id
      AND ph.CreationDate = le.LastEditDate
  )
SELECT
  COALESCE(eu.LastEditorDisplayName, 'Community') AS EditorName,
  eu.LastEditDate,
  eu.OriginalTitle,
  SUBSTRING(eu.OriginalTags FROM 2 FOR LENGTH(eu.OriginalTags) - 2) AS CleanTags,
  eu.AnswerCount,
  COALESCE(ups.TotalPosts, 0) AS EditorTotalPosts,
  COALESCE(ups.QuestionCount, 0) AS EditorQuestionCount,
  COALESCE(ROUND(ups.AvgScore, 2), 0.0) AS EditorAvgScore,
  COUNT(c.Id) AS CommentCountOnEditedPost
FROM EditUsers eu
LEFT JOIN Users u
  ON eu.EditorUserId = u.Id
LEFT JOIN UserPostStats ups
  ON eu.EditorUserId = ups.OwnerUserId
LEFT JOIN Comments c
  ON eu.PostId = c.PostId
GROUP BY
  eu.LastEditorDisplayName,
  eu.LastEditDate,
  eu.OriginalTitle,
  CleanTags,
  eu.AnswerCount,
  ups.TotalPosts,
  ups.QuestionCount,
  ups.AvgScore,
  eu.OriginalTags,
  eu.PostId,
  eu.EditorUserId
HAVING
  COUNT(c.Id) > 5
ORDER BY
  eu.LastEditDate DESC
LIMIT 100;