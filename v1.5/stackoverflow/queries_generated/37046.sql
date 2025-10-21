-- {"query": "37046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2059} 
WITH
-- compute tag popularity and average question score over last 2 years
RecentQuestions AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - INTERVAL '2 years'
),
ExplodedTags AS (
  SELECT
    rq.Id AS QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    trim(tag) AS Tag
  FROM RecentQuestions rq,
       unnest(string_to_array(substr(coalesce(rq.Tags, ''), 2, nullif(length(coalesce(rq.Tags, ''))-2, -1)), '><')) AS tag
  WHERE rq.Tags IS NOT NULL AND rq.Tags <> ''
),
TagStats AS (
  SELECT
    e.Tag,
    count(*) AS QuestionCount,
    avg(e.Score) AS AvgScore,
    avg(e.ViewCount) AS AvgViews,
    count(DISTINCT e.OwnerUserId) FILTER (WHERE e.OwnerUserId IS NOT NULL) AS DistinctAskers
  FROM ExplodedTags e
  GROUP BY e.Tag
),
-- for top tags, find hot questions and answerer activity
TopTags AS (
  SELECT Tag
  FROM TagStats
  ORDER BY QuestionCount DESC
  LIMIT 25
),
HotQuestions AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId
  FROM Posts q
  JOIN TopTags tt ON POSITION('<' || tt.Tag || '>' IN coalesce(q.Tags, '')) > 0
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - INTERVAL '180 days'
),
AnswersWithLatency AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.CreationDate AS AnswerDate,
         q.CreationDate AS QuestionDate,
         EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToFirstAnswer,
         a.Score AS AnswerScore,
         a.OwnerUserId AS AnswererId
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
    AND q.PostTypeId = 1
    AND q.CreationDate >= now() - INTERVAL '180 days'
),
FirstAnswers AS (
  SELECT awl.QuestionId,
         min(awl.AnswerDate) AS FirstAnswerDate
  FROM AnswersWithLatency awl
  GROUP BY awl.QuestionId
),
AnswererAggregates AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    count(a.Id) FILTER (WHERE a.PostTypeId = 2 AND a.CreationDate >= now()-INTERVAL '1 year') AS AnswersLastYear,
    avg(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
    max(a.Score) FILTER (WHERE a.PostTypeId = 2) AS MaxAnswerScore,
    sum(CASE WHEN a.CreationDate >= now()-INTERVAL '30 days' THEN 1 ELSE 0 END) AS AnswersLast30Days
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- compute per-question enrichment: tags, first answer latency, accept rate, comments, votes
QuestionEnrichment AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.Tags,
    array_agg(DISTINCT tt.Tag) FILTER (WHERE tt.Tag IS NOT NULL) AS MatchedTopTags,
    fq.FirstAnswerDate,
    EXTRACT(EPOCH FROM (fq.FirstAnswerDate - q.CreationDate))/3600.0 AS HoursToFirstAnswer,
    count(DISTINCT ans.Id) AS AnswerCountRealtime,
    count(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    count(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    sum(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
    count(c.Id) AS CommentCount
  FROM HotQuestions q
  LEFT JOIN TopTags tt ON POSITION('<' || tt.Tag || '>' IN coalesce(q.Tags, '')) > 0
  LEFT JOIN FirstAnswers fq ON fq.QuestionId = q.Id
  LEFT JOIN Posts ans ON ans.ParentId = q.Id AND ans.PostTypeId = 2
  LEFT JOIN Votes v ON v.PostId = q.Id
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
  GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, fq.FirstAnswerDate, q.AcceptedAnswerId
),
-- links and duplicates network density per hot question
LinkNetwork AS (
  SELECT
    q.Id AS QuestionId,
    count(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS OutgoingLinks,
    count(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS MarkedDuplicates,
    count(pl2.Id) AS IncomingLinks
  FROM HotQuestions q
  LEFT JOIN PostLinks pl ON pl.PostId = q.Id
  LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = q.Id
  GROUP BY q.Id
),
-- heavy join: get recent editors and history pivots
RecentEdits AS (
  SELECT ph.PostId,
         max(ph.CreationDate) AS LastEdit,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,6,4)) AS EditCount,
         json_agg(json_build_object('Type', pht.Name, 'UserId', ph.UserId, 'When', ph.CreationDate) ORDER BY ph.CreationDate DESC) FILTER (WHERE ph.UserId IS NOT NULL) AS RecentEditors
  FROM PostHistory ph
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  WHERE ph.CreationDate >= now() - INTERVAL '365 days'
  GROUP BY ph.PostId
),
-- final selection joining everything and scoring for benchmark complexity
FinalScoring AS (
  SELECT
    qe.QuestionId,
    qe.Title,
    qe.CreationDate,
    qe.QuestionScore,
    qe.ViewCount,
    qe.MatchedTopTags,
    coalesce(qe.HoursToFirstAnswer, 999999) AS HoursToFirstAnswer,
    qe.AnswerCountRealtime,
    qe.HasAcceptedAnswer,
    qe.UpVotes,
    qe.DownVotes,
    ln.OutgoingLinks,
    ln.MarkedDuplicates,
    ln.IncomingLinks,
    re.LastEdit,
    re.EditCount,
    re.RecentEditors,
    -- heuristics: composite hotness that mixes recency, score, views, answers, and link density
    ( (greatest(0, qe.QuestionScore)::numeric * 2.0)
      + ln.OutgoingLinks * 1.5
      + ln.IncomingLinks * 1.0
      + (case when qe.HasAcceptedAnswer > 0 then 25 else 0 end)
      + (100.0 / nullif(greatest(1, coalesce(qe.HoursToFirstAnswer, 24)), 0))
      + (qe.ViewCount::numeric / nullif(greatest(1, qe.AnswerCountRealtime),1)) ) AS CompositeHotness
  FROM QuestionEnrichment qe
  LEFT JOIN LinkNetwork ln ON ln.QuestionId = qe.QuestionId
  LEFT JOIN RecentEdits re ON re.PostId = qe.QuestionId
)
SELECT
  fs.*,
  ts.QuestionCount AS TagQuestionsIn2Years,
  ts.AvgScore AS TagAvgScore2Y,
  ts.AvgViews AS TagAvgViews2Y,
  aa.UserId AS TopAnswererId,
  aa.DisplayName AS TopAnswererName,
  aa.AnswersLastYear,
  aa.AvgAnswerScore,
  aa.MaxAnswerScore,
  aa.AnswersLast30Days
FROM FinalScoring fs
LEFT JOIN LATERAL (
  -- associate strongest tag stats among matched top tags
  SELECT t.Tag, t.QuestionCount, t.AvgScore, t.AvgViews
  FROM TagStats t
  WHERE t.Tag = ANY(coalesce(fs.MatchedTopTags, ARRAY[]::varchar[]))
  ORDER BY t.QuestionCount DESC NULLS LAST
  LIMIT 1
) ts ON true
LEFT JOIN LATERAL (
  -- pick a prolific answerer who answered this question's answers recently
  SELECT a.UserId, a.DisplayName, a.AnswersLastYear, a.AvgAnswerScore, a.MaxAnswerScore, a.AnswersLast30Days
  FROM AnswererAggregates a
  JOIN Posts p_ans ON p_ans.OwnerUserId = a.UserId
  WHERE p_ans.ParentId = fs.QuestionId
  GROUP BY a.UserId, a.DisplayName, a.AnswersLastYear, a.AvgAnswerScore, a.MaxAnswerScore, a.AnswersLast30Days
  ORDER BY a.AnswersLast30Days DESC, a.AnswersLastYear DESC
  LIMIT 1
) aa ON true
ORDER BY fs.CompositeHotness DESC, fs.QuestionScore DESC, fs.ViewCount DESC
LIMIT 200;