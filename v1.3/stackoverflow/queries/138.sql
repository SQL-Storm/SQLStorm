-- {"query": "138.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2108} 
WITH
-- explode tags into one row per tag per question
ExplodedTags AS (
  SELECT
    p.Id AS QuestionId,
    trim(tg) AS Tag
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''), 2, GREATEST(length(coalesce(p.Tags,''))-2,0)), '><')) AS tg
  ) s
  WHERE pt.Name ILIKE 'question'
),
-- recent activity marker and normalized title/text lengths
QuestionMetrics AS (
  SELECT
    q.Id,
    q.Title,
    q.Tags,
    q.OwnerUserId,
    q.CreationDate,
    q.LastActivityDate,
    COALESCE(q.ViewCount,0) AS ViewCount,
    COALESCE(q.Score,0) AS Score,
    length(coalesce(q.Title,'')) AS TitleLen,
    length(coalesce(q.Body,'')) AS BodyLen,
    CASE
      WHEN q.LastActivityDate IS NULL THEN 'no_activity'
      WHEN q.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' THEN 'active_30d'
      WHEN q.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' THEN 'active_year'
      ELSE 'stale'
    END AS ActivityBin
  FROM Posts q
  WHERE q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name ILIKE 'question' LIMIT 1)
),
-- answers linked to their questions
Answers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    a.CreationDate AS AnswerDate,
    COALESCE(a.Score,0) AS AnswerScore,
    CASE WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.Id = a.ParentId AND q.AcceptedAnswerId = a.Id) THEN 1 ELSE 0 END AS IsAccepted,
    length(coalesce(a.Body,'')) AS AnswerBodyLen
  FROM Posts a
  WHERE a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name ILIKE 'answer' LIMIT 1)
),
-- per-question aggregates (correlated subqueries demonstrating correlated behavior)
PerQuestionAgg AS (
  SELECT
    qm.*,
    (SELECT COUNT(*) FROM Answers ans WHERE ans.QuestionId = qm.Id) AS AnswerCount_Internal,
    (SELECT SUM(AnswerScore) FROM Answers ans WHERE ans.QuestionId = qm.Id) AS SumAnswerScore_Internal,
    (SELECT MAX(AnswerScore) FROM Answers ans WHERE ans.QuestionId = qm.Id) AS MaxAnswerScore_Internal,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qm.Id AND c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') AS RecentCommentCount
  FROM QuestionMetrics qm
),
-- tag-level aggregates using window functions and joins
TagAggregates AS (
  SELECT
    e.Tag,
    COUNT(DISTINCT pq.Id) AS QuestionsCount,
    SUM(COALESCE(pq.AnswerCount_Internal,0)) AS TotalAnswers,
    AVG(COALESCE(pq.ViewCount,0)) AS AvgViews,
    SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.Id = pq.Id AND q.AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
    AVG(COALESCE(pq.Score,0)) AS AvgQuestionScore,
    SUM(COALESCE(pq.RecentCommentCount,0)) AS RecentComments90d,
    -- median of answer scores per tag using ordered-set aggregate
    percentile_disc(0.5) WITHIN GROUP (ORDER BY COALESCE(a.AnswerScore,0)) AS MedianAnswerScore,
    -- top contributor per tag via window functions: user with highest sum of answer score within tag
    (SELECT u.DisplayName
     FROM (
       SELECT ans.OwnerUserId, SUM(ans.AnswerScore) AS ScoreSum
       FROM Answers ans
       JOIN ExplodedTags et2 ON et2.QuestionId = ans.QuestionId
       WHERE et2.Tag = e.Tag AND ans.OwnerUserId IS NOT NULL
       GROUP BY ans.OwnerUserId
       ORDER BY ScoreSum DESC NULLS LAST
       LIMIT 1
     ) topu
     LEFT JOIN Users u ON u.Id = topu.OwnerUserId
    ) AS TopAnswererDisplayName,
    -- diversity metric: number of distinct answerers
    (SELECT COUNT(DISTINCT ans.OwnerUserId) FROM Answers ans JOIN ExplodedTags et3 ON et3.QuestionId = ans.QuestionId WHERE et3.Tag = e.Tag AND ans.OwnerUserId IS NOT NULL) AS DistinctAnswerers,
    -- ratio expressed using NULL-safe logic
    CASE WHEN COUNT(DISTINCT pq.Id) = 0 THEN NULL ELSE ROUND(100.0 * SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.Id = pq.Id AND q.AcceptedAnswerId IS NOT NULL) THEN 1.0 ELSE 0.0 END) / COUNT(DISTINCT pq.Id),2) END AS PercentWithAccepted
  FROM ExplodedTags e
  LEFT JOIN PerQuestionAgg pq ON pq.Id = e.QuestionId
  LEFT JOIN Answers a ON a.QuestionId = pq.Id
  GROUP BY e.Tag
),
-- identify users with badges but no questions (set operators)
UsersWithBadges AS (
  SELECT DISTINCT b.UserId FROM Badges b WHERE b.UserId IS NOT NULL
),
ActiveQuestionAskers AS (
  SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = (SELECT Id FROM PostTypes WHERE Name ILIKE 'question' LIMIT 1) AND OwnerUserId IS NOT NULL
),
BadgeNoAskers AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation
  FROM Users u
  WHERE u.Id IN (SELECT UserId FROM UsersWithBadges)
  EXCEPT
  SELECT OwnerUserId, NULL, NULL FROM ActiveQuestionAskers  -- note: EXCEPT with mismatched columns intentionally to produce non-empty; handled by casting below
),
-- normalize the EXCEPT result correctly (safe re-evaluation)
BadgeNoAskersNormalized AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation
  FROM Users u
  WHERE u.Id IN (SELECT UserId FROM UsersWithBadges)
    AND u.Id NOT IN (SELECT OwnerUserId FROM ActiveQuestionAskers)
),
-- a synthetic row to be UNIONed for comparisons
AllTagsSummary AS (
  SELECT
    '___ALL_TAGS___'::varchar AS Tag,
    SUM(QuestionsCount) AS QuestionsCount,
    SUM(TotalAnswers) AS TotalAnswers,
    AVG(AvgViews) AS AvgViews,
    SUM(QuestionsWithAccepted) AS QuestionsWithAccepted,
    AVG(AvgQuestionScore) AS AvgQuestionScore,
    SUM(RecentComments90d) AS RecentComments90d,
    percentile_disc(0.5) WITHIN GROUP (ORDER BY MedianAnswerScore) AS MedianAnswerScore,
    NULL::varchar AS TopAnswererDisplayName,
    SUM(DistinctAnswerers) AS DistinctAnswerers,
    ROUND(100.0 * SUM(QuestionsWithAccepted) / NULLIF(SUM(QuestionsCount),0),2) AS PercentWithAccepted
  FROM TagAggregates
)
-- final select combining tag aggregates with an overall row and listing a sample of badge-no-askers
SELECT
  ta.Tag,
  ta.QuestionsCount,
  ta.TotalAnswers,
  ROUND(ta.AvgViews,2) AS AvgViews,
  ta.QuestionsWithAccepted,
  ROUND(ta.AvgQuestionScore,3) AS AvgQuestionScore,
  ta.RecentComments90d,
  COALESCE(ta.MedianAnswerScore,0) AS MedianAnswerScore,
  COALESCE(ta.TopAnswererDisplayName,'(none)') AS TopAnswererDisplayName,
  ta.DistinctAnswerers,
  ta.PercentWithAccepted,
  -- add some interesting synthetic metrics using string expressions and null-handling
  CONCAT(
    COALESCE(ta.Tag,'<null>'),
    ' | q=', COALESCE(ta.QuestionsCount::text,'0'),
    ' a=', COALESCE(ta.TotalAnswers::text,'0'),
    ' p=', COALESCE(ta.PercentWithAccepted::text,'0')
  ) AS SummaryLabel
FROM (
  SELECT * FROM TagAggregates
  UNION ALL
  SELECT * FROM AllTagsSummary
) ta
ORDER BY
  -- order by a composite key with NULLS LAST to stress sorting
  (CASE WHEN ta.Tag = '___ALL_TAGS___' THEN 0 ELSE 1 END) ASC,
  ta.QuestionsCount DESC NULLS LAST,
  ta.Tag ASC
LIMIT 250;