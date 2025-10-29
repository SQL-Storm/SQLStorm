WITH
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      ROW_NUMBER() OVER (
        ORDER BY
          u.Reputation DESC,
          u.CreationDate ASC
      ) AS Rank
    FROM
      Users AS u
    WHERE
      u.Reputation > 50000
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.Score AS QuestionScore,
      p.FavoriteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS QuestionStatus
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '90 days')
  ),
  AnswersPerQuestion AS (
    SELECT
      pr.Id AS AnswerId,
      pr.ParentId AS QuestionId,
      pr.OwnerUserId AS AnswererUserId,
      pr.CreationDate AS AnswerCreationDate,
      pr.Score AS AnswerScore,
      ROW_NUMBER() OVER (
        PARTITION BY
          pr.ParentId
        ORDER BY
          pr.Score DESC,
          pr.CreationDate ASC
      ) AS AnswerRank
    FROM
      Posts AS pr
    WHERE
      pr.PostTypeId = 2
  ),
  QuestionAnswerStats AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.QuestionScore,
      rq.FavoriteCount,
      rq.QuestionStatus,
      COALESCE(MAX(apq.AnswerScore), 0) AS MaxAnswerScore,
      COUNT(apq.AnswerId) AS TotalAnswers,
      AVG(apq.AnswerScore) AS AvgAnswerScore,
      SUM(CASE WHEN apq.AnswerRank = 1 THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM
      RecentQuestions AS rq
      LEFT JOIN Users AS u
        ON rq.OwnerUserId = u.Id
      LEFT JOIN AnswersPerQuestion AS apq
        ON rq.QuestionId = apq.QuestionId
    GROUP BY
      rq.QuestionId,
      rq.Title,
      rq.OwnerUserId,
      u.DisplayName,
      rq.QuestionCreationDate,
      rq.AnswerCount,
      rq.QuestionScore,
      rq.FavoriteCount,
      rq.QuestionStatus
  )
SELECT
  qas.QuestionId,
  qas.Title,
  qas.OwnerDisplayName,
  qas.QuestionCreationDate,
  qas.QuestionStatus,
  qas.QuestionScore,
  qas.FavoriteCount,
  qas.TotalAnswers,
  qas.AvgAnswerScore,
  qas.MaxAnswerScore,
  CASE
    WHEN qas.QuestionScore > 0
    AND qas.AvgAnswerScore > 0 THEN CAST(
      (
        qas.QuestionScore + qas.AvgAnswerScore
      ) AS DOUBLE PRECISION
    ) / NULLIF(qas.TotalAnswers,0)
    WHEN qas.QuestionScore > 0 THEN CAST(
      qas.QuestionScore AS DOUBLE PRECISION
    ) / NULLIF(qas.TotalAnswers,0)
    WHEN qas.AvgAnswerScore > 0 THEN CAST(
      qas.AvgAnswerScore AS DOUBLE PRECISION
    ) / NULLIF(qas.TotalAnswers,0)
    ELSE 0
  END AS ScoreRatio,
  CASE
    WHEN hru.UserId IS NOT NULL THEN 'High Rep User'
    ELSE 'Regular User'
  END AS OwnerReputationCategory,
  CONCAT(
    SUBSTRING(qas.Title FROM 1 FOR 50),
    CASE
      WHEN CHAR_LENGTH(qas.Title) > 50 THEN '...'
      ELSE ''
    END
  ) AS ShortTitle,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = qas.QuestionId
        AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate'
    ELSE 'Not Explicitly Duplicate'
  END AS LinkStatus,
  qas.OwnerUserId
FROM
  QuestionAnswerStats AS qas
LEFT JOIN HighReputationUsers AS hru
  ON qas.OwnerUserId = hru.UserId
WHERE
  qas.TotalAnswers > 0
  AND qas.QuestionScore > (
    SELECT
      AVG(p.Score)
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '90 days')
  )
UNION
SELECT
  rq.QuestionId,
  rq.Title,
  u.DisplayName AS OwnerDisplayName,
  rq.QuestionCreationDate,
  rq.QuestionStatus,
  rq.QuestionScore,
  rq.FavoriteCount,
  0 AS TotalAnswers,
  0.0 AS AvgAnswerScore,
  0 AS MaxAnswerScore,
  CAST(rq.QuestionScore AS DOUBLE PRECISION) AS ScoreRatio,
  CASE
    WHEN hru.UserId IS NOT NULL THEN 'High Rep User'
    ELSE 'Regular User'
  END AS OwnerReputationCategory,
  CONCAT(
    SUBSTRING(rq.Title FROM 1 FOR 50),
    CASE
      WHEN CHAR_LENGTH(rq.Title) > 50 THEN '...'
      ELSE ''
    END
  ) AS ShortTitle,
  'No Answers' AS LinkStatus,
  rq.OwnerUserId
FROM
  RecentQuestions AS rq
LEFT JOIN Users AS u
  ON rq.OwnerUserId = u.Id
LEFT JOIN HighReputationUsers AS hru
  ON rq.OwnerUserId = hru.UserId
WHERE
  rq.QuestionId NOT IN (
    SELECT
      QuestionId
    FROM
      QuestionAnswerStats
  )
ORDER BY
  QuestionCreationDate DESC,
  QuestionScore DESC
LIMIT 1000;