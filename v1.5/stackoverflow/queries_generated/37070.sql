-- {"query": "37070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1941} 
WITH
-- recent active questions with tag exploded
Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.OwnerUserId, p.Tags,
         regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '3 years'
),
-- compute per-question accepted answer metrics and fastest accepted answer time
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
-- aggregate per-question stats: number of distinct answerers, median answer score (approx), comments count
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
-- compute tag-level rolling stats over questions
TagQuestionStats AS (
  SELECT Tag,
         COUNT(DISTINCT q.Id) AS QuestionsWithTag,
         AVG(q.Score) AS AvgQuestionScore,
         AVG(q.ViewCount) AS AvgViews,
         AVG(a.TotalAnswers) AS AvgAnswers,
         SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
         AVG(EXTRACT(EPOCH FROM (now() - q.CreationDate))/86400) AS AvgAgeDays
  FROM Questions q
  LEFT JOIN AnswerAggregates a ON a.QuestionId = q.Id
  GROUP BY Tag
),
-- identify users who have high-quality answers: answers in last 3 years with score >= 10 and accepted many times
TopAnswerers AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= now()-interval '3 years' AND a.Score >= 10) AS HighScoreAnswers,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= now()-interval '3 years') AS RecentAnswers,
         SUM(CASE WHEN a.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS TimesAcceptedOverall,
         AVG(a.Score) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= now()-interval '3 years') AS AvgAnswerScoreRecent
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= now()-interval '3 years') >= 5
),
-- join questions with accepted answer timings and answer aggregates, and compute composite "interest" score
QuestionEnrichment AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score AS QuestionScore, q.ViewCount, q.AnswerCount,
         qa.TotalAnswers, qa.DistinctAnswerers, qa.MedianAnswerScore, qa.MaxAnswerScore, qa.CommentCountOnQuestion,
         aa.AnswerId AS AcceptedAnswerId, aa.AnswerOwner, aa.AnswerScore AS AcceptedAnswerScore, aa.SecondsToAccepted,
         CASE
           WHEN q.ViewCount IS NULL OR q.ViewCount = 0 THEN 0
           ELSE (q.Score::numeric * 2 + COALESCE(qa.TotalAnswers,0) * 1.5 + COALESCE(qa.MedianAnswerScore,0) * 3 + (CASE WHEN aa.AnswerId IS NOT NULL THEN 5 ELSE 0 END) + COALESCE(qa.CommentCountOnQuestion,0) * 0.5) / NULLIF(q.ViewCount,0)
         END AS InterestPerView,
         (CASE WHEN aa.SecondsToAccepted IS NOT NULL THEN aa.SecondsToAccepted/3600.0 ELSE NULL END) AS HoursToAccepted
  FROM Questions q
  LEFT JOIN AnswerAggregates qa ON qa.QuestionId = q.Id
  LEFT JOIN AcceptedAnswers aa ON aa.QuestionId = q.Id
),
-- windowed rank per tag: top high-interest questions and also underappreciated questions (high interest but low views)
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
  JOIN TagQuestionStats tq ON tq.Tag = regexp_split_to_table(substring(q.Tags,2,length(q.Tags)-2), '><')
  JOIN QuestionEnrichment qe ON qe.Id = q.Id
),
-- focus set: tags with enough activity and interesting distribution
ActiveTags AS (
  SELECT Tag
  FROM TagQuestionStats
  WHERE QuestionsWithTag >= 250
    AND AvgAnswers >= 2
    AND AvgViews >= 1000
    AND AvgQuestionScore IS NOT NULL
)
-- final selection: for top tags, pick top 5 interest questions, top 5 underappreciated, and summary stats
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
       ROUND(tr.InterestPerView::numeric,6) AS InterestPerView,
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
       ROUND(tr.InterestPerView::numeric,6) AS InterestPerView,
       tr.RankUnderappreciated AS RankInTag,
       tr.QuestionsInTag
FROM ActiveTags at
JOIN TagRankings tr ON tr.Tag = at.Tag AND tr.RankUnderappreciated <= 5

UNION ALL

-- tag-level summaries appended
SELECT t.Tag,
       'Summary' AS Category,
       NULL::bigint AS QuestionId,
       NULL::varchar AS Title,
       NULL::int AS QuestionScore,
       NULL::int AS ViewCount,
       NULL::int AS TotalAnswers,
       NULL::numeric AS MedianAnswerScore,
       NULL::bigint AS AcceptedAnswerId,
       NULL::int AS AcceptedAnswerScore,
       NULL::numeric AS HoursToAccepted,
       ROUND(tqs.AvgQuestionScore::numeric,6) AS InterestPerView,
       tqs.QuestionsWithTag AS RankInTag,
       NULL::int AS QuestionsInTag
FROM TagQuestionStats tqs
JOIN ActiveTags t ON t.Tag = tqs.Tag
ORDER BY Tag, Category DESC, RankInTag NULLS LAST;