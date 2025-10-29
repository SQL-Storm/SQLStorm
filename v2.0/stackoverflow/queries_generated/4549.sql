-- {"query": "4549.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1420} 

WITH
  RankedPostHistory AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edits: Title, Body, Tags */
  ),
  LatestEdits AS (
    SELECT
      rph.PostId,
      rph.UserId AS LastEditorUserId,
      rph.CreationDate AS LastEditDate
    FROM RankedPostHistory AS rph
    WHERE
      rph.rn = 1
  ),
  QuestionsWithAnswers AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.Tags AS QuestionTags,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN a.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts AS p
    LEFT JOIN Posts AS a
      ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1 /* Question */
    GROUP BY
      p.Id,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      p.CreationDate
  ),
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts
    FROM Posts
    GROUP BY
      OwnerUserId
  ),
  UserQuestionsAnswered AS (
    SELECT
      pu.OwnerUserId,
      COUNT(DISTINCT q.QuestionId) AS QuestionsAnswered
    FROM Posts AS a
    JOIN Posts AS q
      ON a.ParentId = q.Id
    WHERE
      a.PostTypeId = 2 /* Answer */ AND q.PostTypeId = 1 /* Question */
    GROUP BY
      pu.OwnerUserId
  ),
  UserContributionMetrics AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COALESCE(upc.TotalPosts, 0) AS TotalPosts,
      COALESCE(uqa.QuestionsAnswered, 0) AS QuestionsAnswered,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1 /* Gold Badge */
      ) AS GoldBadges,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 2 /* Silver Badge */
      ) AS SilverBadges,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 3 /* Bronze Badge */
      ) AS BronzeBadges,
      CASE WHEN u.Views IS NULL THEN 0 ELSE u.Views END AS TotalViews
    FROM Users AS u
    LEFT JOIN UserPostCounts AS upc
      ON u.Id = upc.OwnerUserId
    LEFT JOIN UserQuestionsAnswered AS uqa
      ON u.Id = uqa.OwnerUserId
  )
SELECT
  qwa.QuestionId,
  qwa.QuestionTitle,
  qwa.QuestionTags,
  qwa.QuestionCreationDate,
  le.LastEditorUserId,
  le.LastEditDate,
  COALESCE(qwa.AnswerCount, 0) AS AnswerCount,
  COALESCE(qwa.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
  CASE
    WHEN qwa.AcceptedAnswerCount > 0 THEN CAST(qwa.AcceptedAnswerCount AS REAL) / qwa.AnswerCount
    ELSE 0.0
  END AS AcceptanceRate,
  ucm.DisplayName AS QuestionOwnerDisplayName,
  ucm.Reputation AS QuestionOwnerReputation,
  ucm.TotalPosts AS QuestionOwnerTotalPosts,
  ucm.QuestionsAnswered AS QuestionOwnerQuestionsAnswered,
  ucm.GoldBadges AS QuestionOwnerGoldBadges,
  ucm.SilverBadges AS QuestionOwnerSilverBadges,
  ucm.BronzeBadges AS QuestionOwnerBronzeBadges,
  ucm.TotalViews AS QuestionOwnerTotalViews,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = qwa.QuestionId AND c.Score > 10
  ) AS HighScoreCommentCount,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = qwa.QuestionId AND ph.PostHistoryTypeId = 19 /* Question Protected */
  ) AS ProtectionEvents,
  CASE
    WHEN qwa.QuestionTitle LIKE '%SQL%' THEN 'SQL Related'
    WHEN qwa.QuestionTitle LIKE '%Database%' THEN 'Database Related'
    ELSE 'Other'
  END AS TitleCategory,
  UPPER(SUBSTRING(qwa.QuestionTags, 2, CHARINDEX('><', qwa.QuestionTags) - 2)) AS FirstTag,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = qwa.QuestionId AND pl.LinkTypeId = 3 /* Duplicate */
    ) THEN 'Is Duplicate'
    ELSE 'Not a Duplicate'
  END AS DuplicateStatus
FROM QuestionsWithAnswers AS qwa
FULL OUTER JOIN LatestEdits AS le
  ON qwa.QuestionId = le.PostId
LEFT JOIN UserContributionMetrics AS ucm
  ON qwa.QuestionOwnerUserId = ucm.UserId
WHERE
  qwa.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND qwa.AnswerCount > 5
  AND qwa.QuestionOwnerReputation > 1000
ORDER BY
  qwa.QuestionCreationDate DESC,
  qwa.AnswerCount DESC;
