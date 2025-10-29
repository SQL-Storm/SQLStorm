-- {"query": "4201.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1003} 

WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS QuestionRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT a.Id) AS TotalAnswers,
      SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM Users AS u
    JOIN Posts AS a
      ON u.Id = a.OwnerUserId
    WHERE
      a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  UserPostHistory AS (
    SELECT
      ph.UserId,
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate AS HistoryDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS HistoryRank
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (2, 5) /* Body edits */
  ),
  FrequentEditors AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT ph.PostId) AS EditedPostsCount,
      AVG(DATEDIFF(minute, p.CreationDate, ph.CreationDate)) AS AvgTimeToFirstEdit
    FROM PostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (2, 5) AND ph.UserId IS NOT NULL
    GROUP BY
      ph.UserId
    HAVING
      COUNT(DISTINCT ph.PostId) > 10
  )
SELECT
  COALESCE(u.DisplayName, 'Deleted User') AS UserName,
  rq.QuestionRank,
  uas.TotalAnswers,
  uas.PositiveScoreAnswers,
  ROUND(uas.AverageAnswerScore, 2) AS AvgAnswerScore,
  DATEDIFF(day, uas.LastAnswerDate, GETDATE()) AS DaysSinceLastAnswer,
  COUNT(DISTINCT c.Id) AS UserComments,
  f.EditedPostsCount,
  f.AvgTimeToFirstEdit,
  CASE
    WHEN u.Location LIKE '%USA%' THEN 'USA Based'
    WHEN u.Location LIKE '%Canada%' THEN 'Canada Based'
    WHEN u.WebsiteUrl IS NOT NULL THEN 'Has Website'
    ELSE 'No Specific Location/Website'
  END AS LocationCategory,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.PostId ELSE NULL END) AS InitialBodyEdits,
  COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.PostId ELSE NULL END) AS BodyEdits
FROM Users AS u
LEFT JOIN RankedQuestions AS rq
  ON u.Id = rq.OwnerUserId
LEFT JOIN UserAnswerStats AS uas
  ON u.Id = uas.UserId
LEFT JOIN Comments AS c
  ON u.Id = c.UserId
LEFT JOIN FrequentEditors AS f
  ON u.Id = f.UserId
LEFT JOIN UserPostHistory AS uph
  ON u.Id = uph.UserId
LEFT JOIN PostHistory AS ph
  ON u.Id = ph.UserId
WHERE
  u.Id < 100000 AND u.Reputation > 500
GROUP BY
  COALESCE(u.DisplayName, 'Deleted User'),
  rq.QuestionRank,
  uas.TotalAnswers,
  uas.PositiveScoreAnswers,
  uas.AverageAnswerScore,
  uas.LastAnswerDate,
  f.EditedPostsCount,
  f.AvgTimeToFirstEdit,
  LocationCategory
HAVING
  uas.TotalAnswers IS NOT NULL OR COUNT(DISTINCT c.Id) > 0 OR f.EditedPostsCount IS NOT NULL
ORDER BY
  u.Reputation DESC,
  rq.QuestionRank ASC NULLS LAST;
