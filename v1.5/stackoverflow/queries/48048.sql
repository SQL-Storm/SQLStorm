WITH QuestionDetails AS (
  SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.Score AS QuestionScore,
    p.ViewCount AS QuestionViewCount,
    p.AnswerCount AS QuestionAnswerCount,
    p.CreationDate AS QuestionCreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
      SELECT
        COUNT(*)
      FROM Posts AS a
      WHERE
        a.ParentId = p.Id AND a.PostTypeId = 2
    ) AS AnswerCountSubquery
  FROM Posts AS p
  JOIN Users AS u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 AND p.Score > 100 AND p.ViewCount > 10000
),
AnswerStats AS (
  SELECT
    ParentId,
    COUNT(*) AS NumberOfAnswers,
    AVG(Score) AS AverageAnswerScore,
    MAX(CreationDate) AS LatestAnswerDate
  FROM Posts
  WHERE
    PostTypeId = 2
  GROUP BY
    ParentId
)
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  COALESCE(as_NumberOfAnswers, 0) AS TotalAnswers,
  COALESCE(as_AverageAnswerScore, 0) AS AvgAnswerScore,
  as_LatestAnswerDate
FROM QuestionDetails AS qd
LEFT JOIN (
  SELECT
    ParentId,
    NumberOfAnswers AS as_NumberOfAnswers,
    AverageAnswerScore AS as_AverageAnswerScore,
    LatestAnswerDate AS as_LatestAnswerDate
  FROM AnswerStats
) AS stats ON qd.QuestionId = stats.ParentId
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC,
  stats.as_LatestAnswerDate DESC
LIMIT 100;