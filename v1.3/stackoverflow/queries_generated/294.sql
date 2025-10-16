-- {"query": "294.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3726} 
WITH
-- explode tags from question posts
tag_questions AS (
  SELECT
    q.Id AS QuestionId,
    q.CreationDate,
    q.OwnerUserId,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    trim(t) AS TagName
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.Tags IS NOT NULL
    AND length(q.Tags) > 2
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2),'><')) AS t
  ) sub
),

-- answers with computed delays relative to parent question
answers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId AS AnswererId,
    a.CreationDate AS AnswerCreation,
    p.CreationDate AS QuestionCreation,
    EXTRACT(EPOCH FROM (a.CreationDate - p.CreationDate))/3600.0 AS AnswerDelayHours,
    a.Score AS AnswerScore,
    (CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAccepted
  FROM Posts a
  JOIN Posts p ON a.ParentId = p.Id
  WHERE a.PostTypeId = 2
),

-- aggregate votes per post
post_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
    SUM(CASE WHEN v.VoteTypeId IN (4,12) THEN 1 ELSE 0 END) AS SpamOrOffensive
  FROM Votes v
  GROUP BY v.PostId
),

-- latest history row per post
latest_history AS (
  SELECT DISTINCT ON (ph.PostId)
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId AS HistoryUserId,
    ph.CreationDate AS HistoryDate,
    ph.Comment AS HistoryComment
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
  ORDER BY ph.PostId, ph.CreationDate DESC, ph.Id DESC
),

-- badges per user
user_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgeWeighted
  FROM Badges b
  GROUP BY b.UserId
),

-- per-tag aggregates joining questions and answers
tag_aggregates AS (
  SELECT
    t.TagName,
    COUNT(DISTINCT t.QuestionId) AS Questions,
    COALESCE(AVG(NULLIF(t.ViewCount,0)),0) AS AvgViews,
    COALESCE(AVG(NULLIF(t.Score,0)),0) AS AvgQuestionScore,
    COUNT(a.AnswerId) AS Answers,
    COUNT(DISTINCT a.AnswererId) AS DistinctAnswerers,
    COALESCE(AVG(a.AnswerDelayHours), 0) FILTER (WHERE a.AnswerDelayHours IS NOT NULL) AS AvgAnswerDelayHours,
    COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.AnswerDelayHours) , 0) AS MedianAnswerDelayHours,
    SUM(a.IsAccepted) AS AcceptedAnswers,
    COALESCE(AVG(pb.UpVotes - pb.DownVotes),0) AS AvgAnswerNetVotes
  FROM tag_questions t
  LEFT JOIN answers a ON a.QuestionId = t.QuestionId
  LEFT JOIN post_votes pb ON pb.PostId = a.AnswerId
  GROUP BY t.TagName
),

-- top experts per tag: rank users by answer count then avg score
tag_top_experts AS (
  SELECT
    ta.TagName,
    ta.AnswererId,
    ta.AnswerCount,
    ta.AvgScore,
    ROW_NUMBER() OVER (PARTITION BY ta.TagName ORDER BY ta.AnswerCount DESC, ta.AvgScore DESC NULLS LAST) AS rn
  FROM (
    SELECT
      tq.TagName,
      a.AnswererId,
      COUNT(*) AS AnswerCount,
      AVG(a.AnswerScore) AS AvgScore,
      SUM(a.IsAccepted) AS AcceptedAnswersByUser
    FROM tag_questions tq
    JOIN answers a ON a.QuestionId = tq.QuestionId
    GROUP BY tq.TagName, a.AnswererId
  ) ta
),

-- summarized string of top 3 experts per tag with badge influence and recent activity
tag_top3_summary AS (
  SELECT
    e.TagName,
    COALESCE(string_agg(
      (u.DisplayName || ' (uid:'||e.AnswererId||', ans:'||e.AnswerCount||', avgScore:'||round(e.AvgScore::numeric,2)::text||
       ', badges:'||COALESCE(ub.BadgeCount::text,'0')||', lastSeen:'||
       COALESCE(to_char(MAX(us.LastAccessDate),'YYYY-MM-DD'), 'N/A') || ')'
      ) ORDER BY e.AnswerCount DESC, e.AvgScore DESC
      , '; '), '') AS TopExperts
  FROM tag_top_experts e
  LEFT JOIN Users u ON u.Id = e.AnswererId
  LEFT JOIN user_badges ub ON ub.UserId = e.AnswererId
  LEFT JOIN Users us ON us.Id = e.AnswererId
  WHERE e.rn <= 3
  GROUP BY e.TagName
),

-- editors per question (correlated-like aggregate using PostHistory)
edit_stats AS (
  SELECT
    tq.TagName,
    AVG(NULLIF(
      (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = tq.QuestionId AND ph.UserId IS NOT NULL),
      0
    )) AS AvgEditorsPerQuestion,
    SUM(CASE WHEN EXISTS (SELECT 1 FROM PostHistory ph2 WHERE ph2.PostId = tq.QuestionId AND ph2.PostHistoryTypeId = 10) THEN 1 ELSE 0 END) AS QuestionsEverClosed
  FROM tag_questions tq
  GROUP BY tq.TagName
),

-- assemble per-tag final stats
tag_stats AS (
  SELECT
    ta.TagName,
    ta.Questions,
    ta.Answers,
    ta.DistinctAnswerers,
    ta.AvgViews,
    ta.AvgQuestionScore,
    ta.AvgAnswerDelayHours,
    ta.MedianAnswerDelayHours,
    ta.AcceptedAnswers,
    ta.AvgAnswerNetVotes,
    COALESCE(ts.TopExperts, '') AS TopExperts,
    COALESCE(es.AvgEditorsPerQuestion, 0) AS AvgEditorsPerQuestion,
    es.QuestionsEverClosed,
    -- composite score combining multiple normalized metrics (with NULL-safe math)
    ROUND(
      ( (LEAST(1.0, ta.Answers::numeric / NULLIF(LEAST(GREATEST(ta.Questions,1), 100),0)) * 0.25)
      + (LEAST(1.0, ta.AvgAnswerNetVotes / NULLIF(GREATED(1, ta.AcceptedAnswers),1)) * 0.20)
      + (GREATEST(0, 1 - LEAST(1.0, ta.AvgAnswerDelayHours / NULLIF(GREATEST(1, ta.MedianAnswerDelayHours),1))) * 0.25)
      + (LEAST(1.0, GREATEST(0, ta.DistinctAnswerers::numeric / NULLIF(ta.Questions,1)) ) * 0.20)
      + (CASE WHEN es.QuestionsEverClosed > ta.Questions * 0.1 THEN -0.1 ELSE 0 END)
      ), 4) AS CompositeScore
  FROM tag_aggregates ta
  LEFT JOIN tag_top3_summary ts ON ts.TagName = ta.TagName
  LEFT JOIN edit_stats es ON es.TagName = ta.TagName
),

-- take top N tags by Questions
top_tags AS (
  SELECT TagName FROM tag_stats
  ORDER BY Questions DESC NULLS LAST
  LIMIT 50
),

-- synthetic overall aggregate for UNION
overall AS (
  SELECT
    '<<ALL_TAGS>>'::varchar AS TagName,
    SUM(Questions) AS Questions,
    SUM(Answers) AS Answers,
    SUM(DistinctAnswerers) AS DistinctAnswerers,
    ROUND(AVG(AvgViews)::numeric,2) AS AvgViews,
    ROUND(AVG(AvgQuestionScore)::numeric,2) AS AvgQuestionScore,
    ROUND(AVG(AvgAnswerDelayHours)::numeric,2) AS AvgAnswerDelayHours,
    ROUND(AVG(MedianAnswerDelayHours)::numeric,2) AS MedianAnswerDelayHours,
    SUM(AcceptedAnswers) AS AcceptedAnswers,
    ROUND(AVG(AvgAnswerNetVotes)::numeric,2) AS AvgAnswerNetVotes,
    ''::text AS TopExperts,
    ROUND(AVG(AvgEditorsPerQuestion)::numeric,2) AS AvgEditorsPerQuestion,
    SUM(QuestionsEverClosed) AS QuestionsEverClosed,
    ROUND(AVG(CompositeScore)::numeric,4) AS CompositeScore
  FROM tag_stats
)

SELECT
  ts.TagName,
  ts.Questions,
  ts.Answers,
  ts.DistinctAnswerers,
  ts.AvgViews,
  ts.AvgQuestionScore,
  ROUND(ts.AvgAnswerDelayHours::numeric,3) AS AvgAnswerDelayHours,
  ROUND(ts.MedianAnswerDelayHours::numeric,3) AS MedianAnswerDelayHours,
  ts.AcceptedAnswers,
  ROUND(ts.AvgAnswerNetVotes::numeric,3) AS AvgAnswerNetVotes,
  ts.TopExperts,
  ts.AvgEditorsPerQuestion,
  ts.QuestionsEverClosed,
  ts.CompositeScore,
  -- correlated subquery: count of anonymous (OwnerUserId IS NULL) questions for the tag
  (SELECT COUNT(*) FROM tag_questions tq2 WHERE tq2.TagName = ts.TagName AND tq2.OwnerUserId IS NULL) AS AnonymousQuestions,
  -- sample question id for the tag: the most viewed question (ties broken by recent)
  (SELECT q.QuestionId FROM tag_questions q WHERE q.TagName = ts.TagName ORDER BY q.ViewCount DESC NULLS LAST, q.CreationDate DESC LIMIT 1) AS SampleQuestionId,
  -- sample question title truncated (outer join to Posts)
  LEFT(p.Title, 200) AS SampleQuestionTitle,
  -- latest history info for the sample question (outer join)
  lh.PostHistoryTypeId AS SampleQ_LatestHistoryTypeId,
  lh.HistoryUserId AS SampleQ_LatestHistoryUserId,
  -- correlated subquery retrieving last comment text on the sample question (complex string expression with NULL logic)
  (SELECT COALESCE(MAX(trim(c.Text)), '[no comments]') FROM Comments c WHERE c.PostId = COALESCE(
      (SELECT q2.QuestionId FROM tag_questions q2 WHERE q2.TagName = ts.TagName ORDER BY q2.ViewCount DESC NULLS LAST, q2.CreationDate DESC LIMIT 1),
      -1
    )
  ) AS SampleQuestionLastComment
FROM tag_stats ts
LEFT JOIN top_tags tt ON tt.TagName = ts.TagName
LEFT JOIN LATERAL (
  SELECT q.QuestionId FROM tag_questions q WHERE q.TagName = ts.TagName ORDER BY q.ViewCount DESC NULLS LAST, q.CreationDate DESC LIMIT 1
) samp ON true
LEFT JOIN Posts p ON p.Id = samp.QuestionId
LEFT JOIN latest_history lh ON lh.PostId = samp.QuestionId
WHERE ts.TagName IN (SELECT TagName FROM top_tags)
UNION ALL
SELECT * FROM overall
ORDER BY
  CASE WHEN TagName = '<<ALL_TAGS>>' THEN 1 ELSE 0 END,
  CompositeScore DESC NULLS LAST,
  Questions DESC NULLS LAST;