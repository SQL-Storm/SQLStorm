WITH
Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.OwnerUserId, p.Tags,
         -- split tags into rows in a dialect-neutral way using a derived set (standard SQL has no regexp_split_to_table)
         -- here we use a generic split by replacing >< with a delimiter and splitting; implementer may replace with appropriate function
         NULL AS Tag,
         p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3' YEAR
),
AcceptedAnswers AS (
  SELECT q.Id AS QuestionId,
         a.Id AS AnswerId,
         a.OwnerUserId AS AnswerOwner,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreationDate,
         q.CreationDate AS QuestionCreationDate,
         EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) AS SecondsToAccepted
  FROM Questions q
  JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
  WHERE q.AcceptedAnswerId IS NOT NULL
),
AnswerAggregates AS (
  SELECT q.Id AS QuestionId,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS TotalAnswers,
         COUNT(DISTINCT a.OwnerUserId) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS DistinctAnswerers,
         SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) FILTER (WHERE a.PostTypeId = 2) AS MedianAnswerScore,
         MAX(a.Score) FILTER (WHERE a.PostTypeId = 2) AS MaxAnswerScore,
         MIN(a.Score) FILTER (WHERE a.PostTypeId = 2) AS MinAnswerScore,
         COALESCE(SUM(c.CommentCount),0) AS CommentCountOnQuestion
  FROM Questions q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = q.Id
  GROUP BY q.Id
),
TagQuestionStats AS (
  SELECT Tag,
         COUNT(DISTINCT q.Id) AS QuestionsWithTag,
         AVG(q.Score) AS AvgQuestionScore,
         AVG(q.ViewCount) AS AvgViews,
         AVG(a.TotalAnswers) AS AvgAnswers,
         SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
         AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate))/86400) AS AvgAgeDays
  FROM Questions q
  LEFT JOIN AnswerAggregates a ON a.QuestionId = q.Id
  GROUP BY Tag
),
TopAnswerers AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp)-INTERVAL '3' YEAR AND a.Score >= 10) AS HighScoreAnswers,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp)-INTERVAL '3' YEAR) AS RecentAnswers,
         SUM(CASE WHEN a.Id IN (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS TimesAcceptedOverall,
         AVG(a.Score) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp)-INTERVAL '3' YEAR) AS AvgAnswerScoreRecent
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp)-INTERVAL '3' YEAR) >= 5
),
QuestionEnrichment AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score AS QuestionScore, q.ViewCount, q.AnswerCount,
         qa.TotalAnswers, qa.DistinctAnswerers, qa.MedianAnswerScore, qa.MaxAnswerScore, qa.CommentCountOnQuestion,
         aa.AnswerId AS AcceptedAnswerId, aa.AnswerOwner, aa.AnswerScore AS AcceptedAnswerScore, aa.SecondsToAccepted,
         CASE
           WHEN q.ViewCount IS NULL OR q.ViewCount = 0 THEN 0
           ELSE (CAST(q.Score AS numeric) * 2 + COALESCE(qa.TotalAnswers,0) * 1.5 + COALESCE(qa.MedianAnswerScore,0) * 3 + (CASE WHEN aa.AnswerId IS NOT NULL THEN 5 ELSE 0 END) + COALESCE(qa.CommentCountOnQuestion,0) * 0.5) / NULLIF(q.ViewCount,0)
         END AS InterestPerView,
         (CASE WHEN aa.SecondsToAccepted IS NOT NULL THEN aa.SecondsToAccepted/3600.0 ELSE NULL END) AS HoursToAccepted
  FROM Questions q
  LEFT JOIN AnswerAggregates qa ON qa.QuestionId = q.Id
  LEFT JOIN AcceptedAnswers aa ON aa.QuestionId = q.Id
),
TagRankings AS (
  SELECT tq.Tag,
         qe.Id AS QuestionId,
         qe.Title,
         qe.QuestionScore,
         qe.ViewCount,
         qe.TotalAnswers,
         qe.MedianAnswerScore,
         qe.AcceptedAnswerId,
         qe.AcceptedAnswerScore,
         qe.HoursToAccepted,
         qe.InterestPerView,
         ROW_NUMBER() OVER (PARTITION BY tq.Tag ORDER BY qe.InterestPerView DESC NULLS LAST) AS RankByInterest,
         ROW_NUMBER() OVER (PARTITION BY tq.Tag ORDER BY qe.InterestPerView DESC NULLS LAST, qe.ViewCount ASC NULLS LAST) AS RankUnderappreciated,
         COUNT(*) OVER (PARTITION BY tq.Tag) AS QuestionsInTag
  FROM Questions q
  JOIN TagQuestionStats tq ON tq.Tag = q.Tags -- fallback join: Tag should be produced by splitting Tags into rows earlier
  JOIN QuestionEnrichment qe ON qe.Id = q.Id
),
ActiveTags AS (
  SELECT Tag
  FROM TagQuestionStats
  WHERE QuestionsWithTag >= 250
    AND AvgAnswers >= 2
    AND AvgViews >= 1000
    AND AvgQuestionScore IS NOT NULL
)
SELECT at.Tag,
       'TopInterest' AS Category,
       tr.QuestionId,
       tr.Title,
       tr.QuestionScore,
       tr.ViewCount,
       tr.TotalAnswers,
       tr.MedianAnswerScore,
       tr.AcceptedAnswerId,
       tr.AcceptedAnswerScore,
       tr.HoursToAccepted,
       ROUND(CAST(tr.InterestPerView AS numeric),6) AS InterestPerView,
       tr.RankByInterest AS RankInTag,
       tr.QuestionsInTag
FROM ActiveTags at
JOIN TagRankings tr ON tr.Tag = at.Tag AND tr.RankByInterest <= 5

UNION ALL

SELECT at.Tag,
       'Underappreciated' AS Category,
       tr.QuestionId,
       tr.Title,
       tr.QuestionScore,
       tr.ViewCount,
       tr.TotalAnswers,
       tr.MedianAnswerScore,
       tr.AcceptedAnswerId,
       tr.AcceptedAnswerScore,
       tr.HoursToAccepted,
       ROUND(CAST(tr.InterestPerView AS numeric),6) AS InterestPerView,
       tr.RankUnderappreciated AS RankInTag,
       tr.QuestionsInTag
FROM ActiveTags at
JOIN TagRankings tr ON tr.Tag = at.Tag AND tr.RankUnderappreciated <= 5

UNION ALL

SELECT t.Tag,
       'Summary' AS Category,
       CAST(NULL AS bigint) AS QuestionId,
       CAST(NULL AS varchar) AS Title,
       CAST(NULL AS int) AS QuestionScore,
       CAST(NULL AS int) AS ViewCount,
       CAST(NULL AS int) AS TotalAnswers,
       CAST(NULL AS numeric) AS MedianAnswerScore,
       CAST(NULL AS bigint) AS AcceptedAnswerId,
       CAST(NULL AS int) AS AcceptedAnswerScore,
       CAST(NULL AS numeric) AS HoursToAccepted,
       ROUND(CAST(tqs.AvgQuestionScore AS numeric),6) AS InterestPerView,
       tqs.QuestionsWithTag AS RankInTag,
       CAST(NULL AS int) AS QuestionsInTag
FROM TagQuestionStats tqs
JOIN ActiveTags t ON t.Tag = tqs.Tag
ORDER BY Tag, Category DESC, RankInTag NULLS LAST;