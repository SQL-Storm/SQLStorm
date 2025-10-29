-- {"query": "4616.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1219} 

WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Users AS u
      JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId IN (1, 2)
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM
      Users
    WHERE
      Reputation > 10000
  ),
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      AnswerCount,
      FavoriteCount
    FROM
      Posts
    WHERE
      PostTypeId = 1
      AND CreationDate >= DATE('now', '-30 days')
  ),
  QuestionMetrics AS (
    SELECT
      rq.Id AS QuestionId,
      rq.Title,
      rq.Tags,
      rq.CreationDate,
      ua.DisplayName AS OwnerDisplayName,
      ua.TotalScore AS OwnerTotalScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY rq.CreationDate DESC) AS RowNum
    FROM
      RecentQuestions AS rq
      JOIN UserActivity AS ua
      ON rq.OwnerUserId = ua.UserId
    WHERE
      ua.UserId IN (
        SELECT
          Id
        FROM
          HighReputationUsers
      )
  ),
  AnswerDetails AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCountForQuestion,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(p.Score) AS AvgAnswerScore,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  QuestionWithAnswers AS (
    SELECT
      qm.*,
      ad.AnswerCountForQuestion,
      ad.TotalAnswerScore,
      ad.AvgAnswerScore,
      ad.LastAnswerDate
    FROM
      QuestionMetrics AS qm
      LEFT JOIN AnswerDetails AS ad
      ON qm.QuestionId = ad.QuestionId
  ),
  TopAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      p.Id AS AnswerId,
      p.OwnerUserId,
      u.DisplayName AS AnswerOwnerDisplayName,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank
    FROM
      Posts AS p
      JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
      AND p.ParentId IN (SELECT QuestionId FROM QuestionMetrics)
  ),
  AggregatedData AS (
    SELECT
      qwa.*,
      ta.AnswerId AS TopAnswerId,
      ta.AnswerOwnerDisplayName AS TopAnswerOwner,
      ta.AnswerScore AS TopAnswerScore
    FROM
      QuestionWithAnswers AS qwa
      LEFT JOIN TopAnswers AS ta
      ON qwa.QuestionId = ta.QuestionId AND ta.Rank = 1
  )
SELECT
  ad.QuestionId,
  ad.Title,
  ad.OwnerDisplayName,
  ad.OwnerTotalScore,
  ad.CreationDate AS QuestionCreationDate,
  ad.AnswerCount,
  ad.FavoriteCount,
  ad.AnswerCountForQuestion,
  COALESCE(ad.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(ad.AvgAnswerScore, 0) AS AvgAnswerScore,
  ad.LastAnswerDate,
  ad.TopAnswerId,
  ad.TopAnswerOwner,
  ad.TopAnswerScore,
  CASE
    WHEN ad.QuestionCreationDate < DATE('now', '-1 year') THEN 'Old'
    WHEN ad.QuestionCreationDate >= DATE('now', '-1 year') THEN 'Recent'
    ELSE 'Unknown'
  END AS QuestionAgeCategory,
  SUBSTRING(ad.Tags, INSTR(ad.Tags, '>') + 1, INSTR(ad.Tags, '>', INSTR(ad.Tags, '>') + 1) - (INSTR(ad.Tags, '>') + 1)) AS SecondTag
FROM
  AggregatedData AS ad
WHERE
  ad.RowNum <= 100
  AND ad.AnswerCountForQuestion IS NOT NULL
  AND ad.OwnerTotalScore > 5000
UNION
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM
  Users AS u
WHERE
  u.Id NOT IN (SELECT Id FROM HighReputationUsers)
ORDER BY
  QuestionId;
