WITH RecenteAnswersteilung AS (
  SELECT
    p.ParentId AS QuestionId,
    p.Id AS AnswerId,
    p.OwnerUserId,
    u.Reputation,
    p.Score AS AnswerScore,
    1 + ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC NULLS LAST, p.LastActivityDate DESC) AS ScoreRank,
    CONCAT('user: ', COALESCE(u.DisplayName, '<?>')) AS row_ID_long
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ParentId IS NOT NULL
)
SELECT
  QuestionId,
  AnswerId,
  OwnerUserId,
  Reputation,
  AnswerScore,
  ScoreRank,
  row_ID_long
FROM RecenteAnswersteilung
GROUP BY
  QuestionId,
  AnswerId,
  OwnerUserId,
  Reputation,
  AnswerScore,
  ScoreRank,
  row_ID_long;