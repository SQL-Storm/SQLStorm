-- {"query": "18076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1700} 

WITH
  QuestionScores AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.FavoriteCount,
      p.AnswerCount,
      DENSE_RANK() OVER (
        ORDER BY
          p.Score DESC
      ) AS ScoreRank,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate
      ) AS UserQuestionNumber
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      ROW_NUMBER() OVER (
        PARTITION BY
          a.ParentId
        ORDER BY
          a.Score DESC,
          a.CreationDate ASC
      ) AS AnswerRankInQuestion
    FROM Posts AS a
    WHERE
      a.PostTypeId = 2
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.Views AS TotalUserViews,
      COUNT(DISTINCT qs.PostId) AS TotalQuestions,
      COUNT(DISTINCT ad.AnswerId) AS TotalAnswers,
      SUM(qs.QuestionScore) AS TotalQuestionScore,
      SUM(ad.AnswerScore) AS TotalAnswerScore,
      COUNT(DISTINCT b.Id) AS TotalBadges,
      MAX(u.LastAccessDate) AS LastUserAccess
    FROM Users AS u
    LEFT JOIN QuestionScores AS qs
      ON u.Id = qs.OwnerUserId
    LEFT JOIN AnswerDetails AS ad
      ON u.Id = ad.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.Views,
      u.LastAccessDate
  ),
  QuestionAnswerMetrics AS (
    SELECT
      qs.PostId,
      qs.OwnerUserId,
      qs.QuestionCreationDate,
      qs.QuestionScore,
      qs.FavoriteCount,
      qs.AnswerCount,
      qs.ScoreRank,
      ua.Reputation AS OwnerReputation,
      ua.DisplayName AS OwnerDisplayName,
      COALESCE(ad.AnswerId, -1) AS BestAnswerId,
      COALESCE(ad.AnswerScore, 0) AS BestAnswerScore,
      CASE
        WHEN qs.AnswerCount > 0 THEN qs.FavoriteCount * 1.0 / qs.AnswerCount
        ELSE 0
      END AS FavoriteToAnswerRatio,
      CASE
        WHEN qs.QuestionScore > 0 THEN qs.FavoriteCount * 1.0 / qs.QuestionScore
        ELSE 0
      END AS FavoriteToScoreRatio,
      LAG(qs.QuestionScore, 1, 0) OVER (
        ORDER BY
          qs.QuestionCreationDate
      ) AS PreviousQuestionScore,
      LEAD(qs.QuestionScore, 1, 0) OVER (
        ORDER BY
          qs.QuestionCreationDate
      ) AS NextQuestionScore
    FROM QuestionScores AS qs
    LEFT JOIN UserActivity AS ua
      ON qs.OwnerUserId = ua.UserId
    LEFT JOIN AnswerDetails AS ad
      ON qs.PostId = ad.QuestionId
      AND ad.AnswerRankInQuestion = 1
  )
SELECT
  qam.PostId,
  qam.OwnerUserId,
  qam.QuestionCreationDate,
  qam.QuestionScore,
  qam.FavoriteCount,
  qam.AnswerCount,
  qam.ScoreRank,
  qam.OwnerReputation,
  qam.OwnerDisplayName,
  qam.BestAnswerId,
  qam.BestAnswerScore,
  qam.FavoriteToAnswerRatio,
  qam.FavoriteToScoreRatio,
  qam.PreviousQuestionScore,
  qam.NextQuestionScore,
  ua.TotalUserViews,
  ua.TotalQuestions,
  ua.TotalAnswers,
  ua.TotalQuestionScore,
  ua.TotalAnswerScore,
  ua.TotalBadges,
  ua.LastUserAccess,
  CASE
    WHEN qam.QuestionScore > 1000 THEN 'High Score'
    WHEN qam.QuestionScore > 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  UPPER(SUBSTRING(qam.OwnerDisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(qam.OwnerDisplayName FROM 2)) AS FormattedOwnerDisplayName,
  CASE
    WHEN qam.QuestionScore IS NULL THEN 'No Score'
    WHEN qam.FavoriteCount IS NULL THEN 'No Favorites'
    ELSE 'Sufficient Data'
  END AS DataCompleteness
FROM QuestionAnswerMetrics AS qam
JOIN UserActivity AS ua
  ON qam.OwnerUserId = ua.UserId
WHERE
  qam.OwnerReputation > 1000
  AND qam.FavoriteToAnswerRatio BETWEEN 0.1 AND 0.5
  AND ua.TotalUserViews > 5000
  AND qam.QuestionCreationDate > '2023-01-01'
UNION
SELECT
  qam.PostId,
  qam.OwnerUserId,
  qam.QuestionCreationDate,
  qam.QuestionScore,
  qam.FavoriteCount,
  qam.AnswerCount,
  qam.ScoreRank,
  qam.OwnerReputation,
  qam.OwnerDisplayName,
  qam.BestAnswerId,
  qam.BestAnswerScore,
  qam.FavoriteToAnswerRatio,
  qam.FavoriteToScoreRatio,
  qam.PreviousQuestionScore,
  qam.NextQuestionScore,
  ua.TotalUserViews,
  ua.TotalQuestions,
  ua.TotalAnswers,
  ua.TotalQuestionScore,
  ua.TotalAnswerScore,
  ua.TotalBadges,
  ua.LastUserAccess,
  CASE
    WHEN qam.QuestionScore > 1000 THEN 'High Score'
    WHEN qam.QuestionScore > 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  UPPER(SUBSTRING(qam.OwnerDisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(qam.OwnerDisplayName FROM 2)) AS FormattedOwnerDisplayName,
  CASE
    WHEN qam.QuestionScore IS NULL THEN 'No Score'
    WHEN qam.FavoriteCount IS NULL THEN 'No Favorites'
    ELSE 'Sufficient Data'
  END AS DataCompleteness
FROM QuestionAnswerMetrics AS qam
JOIN UserActivity AS ua
  ON qam.OwnerUserId = ua.UserId
WHERE
  qam.OwnerReputation <= 1000
  AND qam.QuestionScore > 50
  AND ua.TotalAnswers > 10
  AND qam.QuestionCreationDate BETWEEN '2022-01-01' AND '2022-12-31';
