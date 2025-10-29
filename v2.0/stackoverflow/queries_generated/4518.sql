-- {"query": "4518.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1079} 

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
      DENSE_RANK() OVER (
        ORDER BY
          p.Score DESC
      ) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionNumberForUser
    FROM Posts AS p
    INNER JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT OUTER JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-365 day')
  ),
  UserAnswerStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS AnswerCountForUser,
      AVG(p.Score) AS AvgAnswerScoreForUser,
      SUM(p.Score) AS TotalAnswerScoreForUser,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts AS p
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
        WHEN uas.AnswerCountForUser > 0 THEN CAST(uas.TotalAnswerScoreForUser AS REAL) / uas.AnswerCountForUser
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
    FROM RecentQuestions AS rq
    LEFT OUTER JOIN UserAnswerStats AS uas
      ON rq.OwnerUserId = uas.OwnerUserId
    LEFT OUTER JOIN Users AS u
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
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = taq.QuestionId AND c.Score < 0
  ) AS NegativeScoreComments,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = taq.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  CASE
    WHEN taq.UserLocation IS NULL OR taq.UserLocation = 'Unknown' THEN 1
    ELSE 0
  END AS IsLocationUnknown,
  SUM(taq.QuestionScore) OVER () AS TotalScoreOfAllSelectedQuestions
FROM TopAnsweredQuestions AS taq
WHERE
  taq.QuestionScore > 0 AND taq.AnswerCount > 0
UNION
SELECT
  NULL,
  'Summary',
  NULL,
  NULL,
  NULL,
  SUM(taq.QuestionScore),
  SUM(taq.AnswerCount),
  SUM(taq.FavoriteCount),
  AVG(taq.AvgAnswerScoreForUser),
  AVG(taq.CalculatedAvgAnswerScore),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM TopAnsweredQuestions AS taq
WHERE
  taq.QuestionScore > 0 AND taq.AnswerCount > 0;
