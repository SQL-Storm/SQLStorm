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
      SELECT COUNT(*)
      FROM Posts a
      WHERE a.ParentId = p.Id AND a.PostTypeId = 2
    ) AS AnswerCountSubquery
  FROM Posts p
  JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 AND p.Score > 100 AND p.ViewCount > 10000
), AnswerStats AS (
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
  COALESCE(ans.NumberOfAnswers, 0) AS TotalAnswers,
  COALESCE(ans.AverageAnswerScore, 0) AS AvgAnswerScore,
  ans.LatestAnswerDate
FROM QuestionDetails qd
LEFT JOIN AnswerStats ans
  ON qd.QuestionId = ans.ParentId
GROUP BY
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  ans.NumberOfAnswers,
  ans.AverageAnswerScore,
  ans.LatestAnswerDate
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC,
  ans.LatestAnswerDate DESC
LIMIT 100;