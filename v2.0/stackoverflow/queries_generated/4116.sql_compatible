WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate,
      Views
    FROM Users
    WHERE
      Reputation >= 10000
  ),
  QuestionAnswerDetails AS (
    SELECT
      q.Id AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.Score) AS MaxAnswerScore,
      MIN(a.Score) AS MinAnswerScore,
      SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS OwnerAnswers
    FROM Posts AS q
    LEFT JOIN Posts AS a
      ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.OwnerUserId
  ),
  QuestionTagPerformance AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Tags,
      COUNT(DISTINCT ph.UserId) AS DistinctEditors,
      MAX(ph.CreationDate) AS LastEditDate
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Title,
      p.Tags
  )
SELECT
  rq.QuestionId,
  rq.QuestionTitle,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.QuestionViewCount,
  rq.FavoriteCount,
  COALESCE(qad.AnswerCount, 0) AS TotalAnswers,
  qad.AvgAnswerScore,
  qad.MaxAnswerScore,
  qad.MinAnswerScore,
  qad.OwnerAnswers,
  qtp.DistinctEditors,
  qtp.LastEditDate,
  (
    SELECT
      SUM(v.BountyAmount)
    FROM Votes AS v
    WHERE
      v.PostId = rq.QuestionId AND v.VoteTypeId = 8
  ) AS TotalBountyAmount,
  CASE
    WHEN rq.RowNum <= 5 THEN 'Top 5 Recent by Owner'
    ELSE 'Other Recent'
  END AS RecencyCategory,
  CASE
    WHEN hru.Reputation IS NOT NULL THEN 'High Rep User'
    ELSE 'Standard User'
  END AS UserTier,
  CASE
    WHEN rq.QuestionScore > 100 AND rq.FavoriteCount > 10 THEN 'Popular'
    WHEN rq.QuestionScore < 0 THEN 'Unpopular'
    ELSE 'Average'
  END AS PopularityBracket,
  LENGTH(rq.QuestionTitle) AS TitleLength,
  CASE
    WHEN POSITION('how to' IN LOWER(rq.QuestionTitle)) > 0 OR POSITION('why is' IN LOWER(rq.QuestionTitle)) > 0 THEN 'How/Why Question'
    WHEN POSITION('what is' IN LOWER(rq.QuestionTitle)) > 0 THEN 'What Question'
    ELSE 'Other Question Type'
  END AS QuestionType,
  CASE
    WHEN rq.AnswerCount IS NULL THEN 'No Answers Recorded'
    WHEN rq.AnswerCount = 0 THEN 'Zero Answers'
    ELSE CAST(rq.AnswerCount AS VARCHAR) || ' Answers'
  END AS AnswerStatus
FROM RecentQuestions AS rq
LEFT JOIN QuestionAnswerDetails AS qad
  ON rq.QuestionId = qad.QuestionId
LEFT JOIN QuestionTagPerformance AS qtp
  ON rq.QuestionId = qtp.QuestionId
LEFT JOIN HighReputationUsers AS hru
  ON rq.OwnerUserId = hru.Id
WHERE
  rq.RowNum <= 20 AND rq.QuestionScore > -5
ORDER BY
  rq.QuestionCreationDate DESC,
  rq.QuestionScore DESC;