-- {"query": "37050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1967} 
WITH
-- users who are "veteran" contributors: created >5 years ago and >1000 reputation
veteran_users AS (
  SELECT Id AS UserId, Reputation, CreationDate
  FROM Users
  WHERE Reputation >= 1000
    AND CreationDate <= now() - interval '5 years'
),
-- questions with tags expanded into one tag per row (tags are stored like "<tag1><tag2>")
question_tags AS (
  SELECT p.Id AS QuestionId,
         p.OwnerUserId,
         p.CreationDate,
         lower(trim(t)) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,'')) - 2,0)),'><')) AS t
  ) s
  WHERE p.PostTypeId = 1
    AND p.Tags IS NOT NULL
),
-- answers with score and age metrics, join to their questions
answers_enriched AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId AS AnswererId,
         a.CreationDate AS AnswerCreation,
         a.Score AS AnswerScore,
         EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/86400.0 AS DaysToAnswer,
         CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
),
-- compute per-question aggregates: first answer time, accepted, avg answer score, distinct answerers
question_answer_aggs AS (
  SELECT q.Id AS QuestionId,
         q.OwnerUserId AS AskerId,
         q.CreationDate AS QuestionCreation,
         COUNT(a.AnswerId) AS AnswerCount,
         MIN(a.DaysToAnswer) FILTER (WHERE a.AnswerId IS NOT NULL) AS FastestAnswerDays,
         AVG(a.AnswerScore) FILTER (WHERE a.AnswerId IS NOT NULL) AS AvgAnswerScore,
         SUM(a.IsAccepted) AS AcceptedCount,
         COUNT(DISTINCT a.AnswererId) AS DistinctAnswerers
  FROM Posts q
  LEFT JOIN answers_enriched a ON a.QuestionId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.OwnerUserId, q.CreationDate
),
-- compute tag-level aggregates over the last 2 years, but also compare to lifetime metrics
tag_recent_question_stats AS (
  SELECT qt.Tag,
         COUNT(DISTINCT qt.QuestionId) FILTER (WHERE qt.CreationDate >= now() - interval '2 years') AS RecentQuestionCount,
         COUNT(DISTINCT qt.QuestionId) AS TotalQuestionCount,
         AVG(qa.FastestAnswerDays) FILTER (WHERE qt.CreationDate >= now() - interval '2 years' AND qa.FastestAnswerDays IS NOT NULL) AS RecentAvgFirstAnswerDays,
         AVG(qa.AvgAnswerScore) FILTER (WHERE qt.CreationDate >= now() - interval '2 years' AND qa.AvgAnswerScore IS NOT NULL) AS RecentAvgAnswerScore,
         AVG(qa.FastestAnswerDays) FILTER (WHERE qa.FastestAnswerDays IS NOT NULL) AS LifetimeAvgFirstAnswerDays,
         AVG(qa.AvgAnswerScore) FILTER (WHERE qa.AvgAnswerScore IS NOT NULL) AS LifetimeAvgAnswerScore,
         SUM(qa.AcceptedCount) FILTER (WHERE qt.CreationDate >= now() - interval '2 years') AS RecentAcceptedAnswers,
         SUM(qa.AcceptedCount) AS LifetimeAcceptedAnswers
  FROM question_tags qt
  JOIN question_answer_aggs qa ON qa.QuestionId = qt.QuestionId
  GROUP BY qt.Tag
),
-- identify "hot" tags: lots of recent traffic and improving answer speed vs lifetime
hot_tags AS (
  SELECT Tag,
         RecentQuestionCount,
         TotalQuestionCount,
         RecentAvgFirstAnswerDays,
         LifetimeAvgFirstAnswerDays,
         RecentAvgAnswerScore,
         LifetimeAvgAnswerScore,
         RecentAcceptedAnswers,
         LifetimeAcceptedAnswers,
         -- signal: more recent questions with faster response and higher accept ratio
         (COALESCE(NULLIF(LifetimeAvgFirstAnswerDays,0),1) / NULLIF(RecentAvgFirstAnswerDays,0)) * 
         (GREATEST(1.0, RecentQuestionCount/NULLIF(TotalQuestionCount,1))) *
         (GREATEST(1.0, (CASE WHEN RecentAvgAnswerScore IS NULL THEN 0 ELSE RecentAvgAnswerScore END) / NULLIF(CASE WHEN LifetimeAvgAnswerScore IS NULL THEN 0 ELSE LifetimeAvgAnswerScore END,0))) AS HotnessScore
  FROM tag_recent_question_stats
  WHERE RecentQuestionCount >= 50 -- threshold for statistical relevance
),
-- for each hot tag, get top veteran answerers by combined score: answers to questions tagged X in last 2 years weighted by acceptance and score and veteran status
veteran_answerer_per_tag AS (
  SELECT
    ht.Tag,
    a.AnswererId,
    u.DisplayName,
    COUNT(*) AS AnswersToTag,
    SUM(a.AnswerScore) AS SumAnswerScore,
    SUM(a.IsAccepted) AS TotalAccepted,
    SUM(
      (1 + (a.AnswerScore::numeric / NULLIF(NULLIF((SELECT AVG(aa.AnswerScore) FROM answers_enriched aa WHERE aa.AnswererId = a.AnswererId),0),0))) 
      * CASE WHEN v.UserId IS NULL THEN 0.8 ELSE 1.2 END
    ) AS VeteranWeightedContribution
  FROM hot_tags ht
  JOIN question_tags qt ON qt.Tag = ht.Tag AND qt.CreationDate >= now() - interval '2 years'
  JOIN answers_enriched a ON a.QuestionId = qt.QuestionId
  LEFT JOIN veteran_users v ON v.UserId = a.AnswererId
  LEFT JOIN Users u ON u.Id = a.AnswererId
  GROUP BY ht.Tag, a.AnswererId, u.DisplayName
  HAVING COUNT(*) >= 3
),
-- pick top 3 veteran contributors per hot tag by weighted contribution
top_veterans_per_tag AS (
  SELECT vpt.Tag,
         vpt.AnswererId,
         vpt.DisplayName,
         vpt.AnswersToTag,
         vpt.SumAnswerScore,
         vpt.TotalAccepted,
         vpt.VeteranWeightedContribution,
         ROW_NUMBER() OVER (PARTITION BY vpt.Tag ORDER BY vpt.VeteranWeightedContribution DESC) AS rn
  FROM veteran_answerer_per_tag vpt
)
-- final report: hot tags with tag metrics and their top 3 veterans and sampling of representative recent questions (with slowest first-answer times)
SELECT
  ht.Tag,
  ht.HotnessScore,
  ht.RecentQuestionCount,
  ht.TotalQuestionCount,
  round(ht.RecentAvgFirstAnswerDays::numeric,3) AS RecentAvgFirstAnswerDays,
  round(ht.LifetimeAvgFirstAnswerDays::numeric,3) AS LifetimeAvgFirstAnswerDays,
  round(ht.RecentAvgAnswerScore::numeric,3) AS RecentAvgAnswerScore,
  round(ht.LifetimeAvgAnswerScore::numeric,3) AS LifetimeAvgAnswerScore,
  COALESCE(tv.TopVeterans, '[]') AS TopVeterans,
  COALESCE(rq.SlowQuestions, '[]') AS SlowRepresentativeQuestions
FROM hot_tags ht
LEFT JOIN LATERAL (
  SELECT json_agg(json_build_object(
            'AnswererId', tvp.AnswererId,
            'DisplayName', tvp.DisplayName,
            'AnswersToTag', tvp.AnswersToTag,
            'SumAnswerScore', tvp.SumAnswerScore,
            'TotalAccepted', tvp.TotalAccepted,
            'VeteranWeightedContribution', round(tvp.VeteranWeightedContribution::numeric,3)
          ) ORDER BY tvp.VeteranWeightedContribution DESC) AS TopVeterans
  FROM top_veterans_per_tag tvp
  WHERE tvp.Tag = ht.Tag AND tvp.rn <= 3
) tv ON true
LEFT JOIN LATERAL (
  -- sample up to 5 recent questions in this tag that had the slowest first answers (i.e., high DaysToFirstAnswer)
  SELECT json_agg(json_build_object(
           'QuestionId', q.Id,
           'Title', left(q.Title,200),
           'QuestionCreation', q.CreationDate,
           'AnswerCount', qa.AnswerCount,
           'FastestAnswerDays', round(qa.FastestAnswerDays::numeric,3),
           'AvgAnswerScore', round(qa.AvgAnswerScore::numeric,3)
         ) ORDER BY qa.FastestAnswerDays DESC NULLS LAST LIMIT 5) AS SlowQuestions
  FROM Posts q
  JOIN question_tags qt2 ON qt2.QuestionId = q.Id AND qt2.Tag = ht.Tag
  JOIN question_answer_aggs qa ON qa.QuestionId = q.Id
  WHERE q.CreationDate >= now() - interval '2 years'
) rq ON true
ORDER BY ht.HotnessScore DESC
LIMIT 25;