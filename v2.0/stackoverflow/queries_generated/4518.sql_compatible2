WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionNumberForUser
    FROM Posts p
    INNER JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
  ),
  UserAnswerStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS AnswerCountForUser,
      AVG(p.Score) AS AvgAnswerScoreForUser,
      SUM(p.Score) AS TotalAnswerScoreForUser,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.OwnerUserId
  ),
  TopAnsweredQuestions AS (
    SELECT
      rq.QuestionId,
      rq.QuestionTitle,
      rq.OwnerUserId,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      uas.AnswerCountForUser,
      uas.AvgAnswerScoreForUser,
      uas.TotalAnswerScoreForUser,
      CASE
        WHEN uas.AnswerCountForUser > 0 THEN CAST(uas.TotalAnswerScoreForUser AS NUMERIC) / uas.AnswerCountForUser
        ELSE 0
      END AS CalculatedAvgAnswerScore,
      u.DisplayName AS OwnerDisplayName,
      CASE
        WHEN rq.QuestionScore > 100 THEN 'High Score'
        WHEN rq.QuestionScore BETWEEN 50 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
      END AS ScoreCategory,
      COALESCE(u.Location, 'Unknown') AS UserLocation,
      ROW_NUMBER() OVER (ORDER BY rq.FavoriteCount DESC, rq.AnswerCount DESC) AS PopularityRank
    FROM RecentQuestions rq
    LEFT JOIN UserAnswerStats uas
      ON rq.OwnerUserId = uas.OwnerUserId
    LEFT JOIN Users u
      ON rq.OwnerUserId = u.Id
    WHERE
      rq.QuestionNumberForUser <= 5
  )
SELECT
  taq.QuestionId,
  taq.QuestionTitle,
  taq.OwnerUserId,
  taq.OwnerDisplayName,
  taq.QuestionCreationDate,
  taq.QuestionScore,
  taq.AnswerCount,
  taq.FavoriteCount,
  taq.AvgAnswerScoreForUser,
  taq.CalculatedAvgAnswerScore,
  taq.ScoreCategory,
  taq.UserLocation,
  taq.PopularityRank,
  (
    SELECT COUNT(*) FROM Comments c WHERE c.PostId = taq.QuestionId AND c.Score < 0
  ) AS NegativeScoreComments,
  (
    SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = taq.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  CASE WHEN taq.UserLocation IS NULL OR taq.UserLocation = 'Unknown' THEN 1 ELSE 0 END AS IsLocationUnknown,
  SUM(taq.QuestionScore) OVER () AS TotalScoreOfAllSelectedQuestions
FROM TopAnsweredQuestions taq
WHERE
  taq.QuestionScore > 0 AND taq.AnswerCount > 0

UNION ALL

SELECT
  CAST(NULL AS BIGINT) AS QuestionId,
  'Summary' AS QuestionTitle,
  CAST(NULL AS BIGINT) AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS QuestionCreationDate,
  SUM(taq.QuestionScore) AS QuestionScore,
  SUM(taq.AnswerCount) AS AnswerCount,
  SUM(taq.FavoriteCount) AS FavoriteCount,
  AVG(taq.AvgAnswerScoreForUser) AS AvgAnswerScoreForUser,
  AVG(taq.CalculatedAvgAnswerScore) AS CalculatedAvgAnswerScore,
  NULL AS ScoreCategory,
  NULL AS UserLocation,
  NULL AS PopularityRank,
  NULL AS NegativeScoreComments,
  NULL AS DuplicateLinks,
  NULL AS IsLocationUnknown,
  SUM(taq.QuestionScore) AS TotalScoreOfAllSelectedQuestions
FROM TopAnsweredQuestions taq
WHERE
  taq.QuestionScore > 0 AND taq.AnswerCount > 0;