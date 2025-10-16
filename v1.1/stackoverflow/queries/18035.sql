WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 2
  ),
  QuestionMetrics AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      COALESCE(
        (
          SELECT
            MAX(ph.CreationDate)
          FROM PostHistory ph
          WHERE
            ph.PostId = q.Id AND ph.PostHistoryTypeId IN (10, 11)
        ),
        q.LastActivityDate
      ) AS LastMajorActivityDate,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.AnswerCount > 100 THEN 'High Answer Count'
        WHEN q.FavoriteCount > 50 THEN 'Popular'
        WHEN q.Score < 0 THEN 'Negative Score'
        ELSE 'Standard'
      END AS QuestionStatusCategory,
      q.Tags
    FROM Posts q
    WHERE
      q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      MAX(p.CreationDate) AS LastPostCreationDate,
      AVG(p.Score) AS AvgPostScore,
      COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TopAnswerers AS (
    SELECT
      ra.AnswererUserId,
      COUNT(DISTINCT ra.QuestionId) AS QuestionsAnswered,
      SUM(ra.Score) AS TotalAnswerScoreReceived
    FROM RankedAnswers ra
    JOIN QuestionMetrics qm
      ON ra.QuestionId = qm.QuestionId
    WHERE
      ra.rn = 1
    GROUP BY
      ra.AnswererUserId
    HAVING
      COUNT(DISTINCT ra.QuestionId) > 5
  )
SELECT
  qm.QuestionId,
  qm.QuestionStatusCategory,
  u_q.DisplayName AS QuestionerDisplayName,
  u_q.Reputation AS QuestionerReputation,
  qm.QuestionScore,
  qm.AnswerCount,
  qm.FavoriteCount,
  qm.QuestionCreationDate,
  qm.ClosedDate,
  COALESCE(ta_for_answerer.QuestionsAnswered, 0) AS NumberOfTopAnswersProvided,
  COALESCE(ta_for_answerer.TotalAnswerScoreReceived, 0) AS ScoreFromTopAnswers,
  CASE
    WHEN qm.ClosedDate IS NOT NULL
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.ClosedDate) > INTERVAL '30 days'
    THEN 'Stale Closed Question'
    WHEN qm.AnswerCount = 0
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.QuestionCreationDate) > INTERVAL '365 days'
    THEN 'Unanswered Old Question'
    WHEN qm.LastMajorActivityDate IS NOT NULL
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.LastMajorActivityDate) > INTERVAL '180 days'
    THEN 'Inactive Question'
    ELSE 'Active or Recently Active'
  END AS QuestionAgeStatus,
  (
    SELECT
      u_c.DisplayName
    FROM Comments c
    JOIN Users u_c
      ON c.UserId = u_c.Id
    WHERE
      c.PostId = qm.QuestionId
    ORDER BY
      c.CreationDate DESC
    FETCH FIRST 1 ROW ONLY
  ) AS LastCommenter,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE
        pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Explicit Duplicates'
  END AS DuplicateStatus,
  REPLACE(REPLACE(qm.Tags, '><', '|'), '<', '') AS FormattedTags
FROM QuestionMetrics qm
LEFT JOIN Users u_q
  ON qm.QuestionerUserId = u_q.Id
LEFT JOIN RankedAnswers ra_for_qm
  ON qm.QuestionId = ra_for_qm.QuestionId AND ra_for_qm.rn = 1
LEFT JOIN TopAnswerers ta_for_answerer
  ON ra_for_qm.AnswererUserId = ta_for_answerer.AnswererUserId
WHERE
  qm.QuestionScore > -10
  AND qm.AnswerCount > 0

UNION ALL

SELECT
  qm.QuestionId,
  qm.QuestionStatusCategory,
  u_q.DisplayName AS QuestionerDisplayName,
  u_q.Reputation AS QuestionerReputation,
  qm.QuestionScore,
  qm.AnswerCount,
  qm.FavoriteCount,
  qm.QuestionCreationDate,
  qm.ClosedDate,
  COALESCE(ta_for_answerer.QuestionsAnswered, 0) AS NumberOfTopAnswersProvided,
  COALESCE(ta_for_answerer.TotalAnswerScoreReceived, 0) AS ScoreFromTopAnswers,
  CASE
    WHEN qm.ClosedDate IS NOT NULL
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.ClosedDate) > INTERVAL '30 days'
    THEN 'Stale Closed Question'
    WHEN qm.AnswerCount = 0
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.QuestionCreationDate) > INTERVAL '365 days'
    THEN 'Unanswered Old Question'
    WHEN qm.LastMajorActivityDate IS NOT NULL
      AND (CAST('2024-10-01 12:34:56' AS timestamp) - qm.LastMajorActivityDate) > INTERVAL '180 days'
    THEN 'Inactive Question'
    ELSE 'Active or Recently Active'
  END AS QuestionAgeStatus,
  (
    SELECT
      u_c.DisplayName
    FROM Comments c
    JOIN Users u_c
      ON c.UserId = u_c.Id
    WHERE
      c.PostId = qm.QuestionId
    ORDER BY
      c.CreationDate DESC
    FETCH FIRST 1 ROW ONLY
  ) AS LastCommenter,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE
        pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Explicit Duplicates'
  END AS DuplicateStatus,
  REPLACE(REPLACE(qm.Tags, '><', '|'), '<', '') AS FormattedTags
FROM QuestionMetrics qm
JOIN Users u_q
  ON qm.QuestionerUserId = u_q.Id
LEFT JOIN RankedAnswers ra_for_qm
  ON qm.QuestionId = ra_for_qm.QuestionId AND ra_for_qm.rn = 1
LEFT JOIN TopAnswerers ta_for_answerer
  ON ra_for_qm.AnswererUserId = ta_for_answerer.AnswererUserId
WHERE
  qm.QuestionScore <= -10
  AND qm.AnswerCount = 0
ORDER BY
  QuestionScore DESC,
  QuestionCreationDate ASC;