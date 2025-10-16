-- {"query": "247.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4665} 
WITH
-- recent questions (last 2 years) with basic normalization
recent_questions AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
    AND CreationDate >= now() - interval '2 years'
),
-- explode tags safely into rows
question_tags AS (
  SELECT
    q.Id AS question_id,
    nullif(trim(t.tag), '') AS tag
  FROM recent_questions q
  CROSS JOIN LATERAL
    regexp_split_to_table(coalesce(substring(q.Tags, 2, greatest(length(coalesce(q.Tags, '')) - 2, 0)), ''), '><') AS t(tag)
  WHERE trim(t.tag) <> ''
),
-- recent answers (last 2 years)
recent_answers AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
    AND CreationDate >= now() - interval '2 years'
),
-- rank answers per question (top by score then oldest)
answer_rank AS (
  SELECT
    a.*,
    row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn,
    rank() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS rnk_ties
  FROM recent_answers a
),
-- top 3 answers per question
top_answers AS (
  SELECT *
  FROM answer_rank
  WHERE rn <= 3
),
-- per-question edit counts and last edit (from PostHistory)
question_edits AS (
  SELECT
    ph.PostId,
    count(*) AS edits_count,
    max(ph.CreationDate) AS last_edit_date,
    min(ph.CreationDate) AS first_edit_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- close / reopen events per post (using PostHistoryTypeIds)
close_events AS (
  SELECT
    ph.PostId,
    count(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,35,36,52,53)) AS close_reopen_events,
    bool_or(ph.PostHistoryTypeId IN (10,35)) AS ever_closed
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- badge summary per user
user_badges AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    count(b.Id) FILTER (WHERE b.Class = 1) AS gold,
    count(b.Id) FILTER (WHERE b.Class = 2) AS silver,
    count(b.Id) FILTER (WHERE b.Class = 3) AS bronze,
    count(b.Id) FILTER (WHERE b.TagBased) AS tag_based,
    coalesce(sum(case when b.Class = 1 then 10 when b.Class = 2 then 3 when b.Class = 3 then 1 else 0 end),0) AS badge_score
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- per-question aggregated vote counts (via Votes)
question_votes AS (
  SELECT
    p.Id AS postid,
    count(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
    count(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
    count(v.Id) FILTER (WHERE v.VoteTypeId = 5 OR v.VoteTypeId = 15) AS special_votes,
    coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) AS vote_balance
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
-- tag-level stats joining questions
tag_stats AS (
  SELECT
    qt.tag,
    count(DISTINCT qt.question_id) AS question_count,
    avg(q.Score) AS avg_question_score,
    max(q.ViewCount) AS max_views,
    sum(q.AnswerCount) AS total_answer_count
  FROM question_tags qt
  JOIN recent_questions q ON q.Id = qt.question_id
  GROUP BY qt.tag
),
-- activity windows and moving aggregates across questions
question_metrics AS (
  SELECT
    q.Id AS question_id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    coalesce(qt_count.question_tags_count, 0) AS tags_per_question,
    coalesce(qe.edits_count,0) AS edits_count,
    coalesce(ce.close_reopen_events,0) AS close_reopen_events,
    coalesce(qv.upvotes,0) AS upvotes,
    coalesce(qv.downvotes,0) AS downvotes,
    coalesce(qv.vote_balance,0) AS vote_balance,
    -- correlated subquery: top answerer name for this question (highest score, earliest)
    (
      SELECT u.DisplayName
      FROM Posts a
      JOIN Users u ON u.Id = a.OwnerUserId
      WHERE a.ParentId = q.Id
      ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
      LIMIT 1
    ) AS top_answerer_name,
    -- correlated subquery: hours until accepted answer if accepted
    (
      SELECT extract(epoch FROM (p.CreationDate - q.CreationDate)) / 3600.0
      FROM Posts p
      WHERE p.Id = q.AcceptedAnswerId
      LIMIT 1
    ) AS hours_to_accept,
    -- snippet
    substring(coalesce(q.Body,''),1,200) AS snippet,
    -- counts from comments
    (
      SELECT count(*) FROM Comments c WHERE c.PostId = q.Id
    ) AS comment_count,
    -- counts of positive-scoring answers
    (
      SELECT count(*) FROM Posts pa WHERE pa.ParentId = q.Id AND pa.Score > 0
    ) AS positive_answer_count,
    -- number of distinct answerers
    (
      SELECT count(DISTINCT pa.OwnerUserId) FROM Posts pa WHERE pa.ParentId = q.Id AND pa.OwnerUserId IS NOT NULL
    ) AS distinct_answerers,
    -- small text expression to test string ops & null logic
    (CASE WHEN strpos(coalesce(q.Title,''),'?') > 0 THEN 'interrogative' WHEN length(coalesce(q.Body,'')) > 1000 THEN 'longbody' ELSE 'short' END) AS title_body_category,
    -- tags count (fast)
    (
      SELECT count(*) FROM question_tags qt2 WHERE qt2.question_id = q.Id
    ) AS tag_count,
    -- last editor display name via correlated subquery
    (
      SELECT ph.UserDisplayName FROM PostHistory ph
      WHERE ph.PostId = q.Id AND ph.UserDisplayName IS NOT NULL
      ORDER BY ph.CreationDate DESC
      LIMIT 1
    ) AS last_editor_displayname
  FROM recent_questions q
  LEFT JOIN (SELECT question_id, count(*) AS question_tags_count FROM question_tags GROUP BY question_id) qt_count ON qt_count.question_id = q.Id
  LEFT JOIN question_edits qe ON qe.PostId = q.Id
  LEFT JOIN close_events ce ON ce.PostId = q.Id
  LEFT JOIN question_votes qv ON qv.postid = q.Id
),
-- add windowed aggregates across question_metrics for trend / percentile testing
question_trends AS (
  SELECT
    qm.*,
    row_number() OVER (ORDER BY qm.CreationDate) AS seq,
    avg(qm.Score) OVER () AS avg_score_all,
    stddev(qm.Score) OVER () AS stddev_score_all,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY qm.Score) OVER () AS median_score_all,
    avg(qm.Score) OVER (ORDER BY qm.CreationDate ROWS BETWEEN 499 PRECEDING AND CURRENT ROW) AS moving_avg_500,
    count(*) FILTER (WHERE qm.upvotes > qm.downvotes) OVER (ORDER BY qm.CreationDate ROWS BETWEEN 999 PRECEDING AND CURRENT ROW) AS recent_more_upvotes
  FROM question_metrics qm
),
-- top actors: users who answered most top-3 answers and their badge scores (uses lateral correlated aggregation)
top_actors AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    count(ta.Id) AS top3_answers_count,
    coalesce(ub.badge_score,0) AS badge_score,
    coalesce(ub.gold,0) AS gold,
    coalesce(ub.silver,0) AS silver,
    coalesce(ub.bronze,0) AS bronze,
    avg(ta.Score) AS avg_top_answer_score,
    max(ta.Score) AS max_top_answer_score
  FROM Users u
  LEFT JOIN top_answers ta ON ta.OwnerUserId = u.Id
  LEFT JOIN user_badges ub ON ub.user_id = u.Id
  GROUP BY u.Id, u.DisplayName, ub.badge_score, ub.gold, ub.silver, ub.bronze
  HAVING count(ta.Id) > 0
  ORDER BY top3_answers_count DESC NULLS LAST, avg_top_answer_score DESC
  LIMIT 250
),
-- a synthetic benchmark union: top questions and top tags and top actors combined into a single unified output
top_questions AS (
  SELECT
    'question'::text AS entity_type,
    qm.question_id::text AS entity_id,
    coalesce(qm.Title, '('||qm.question_id::text||')')::text AS entity_name,
    qm.Score::int AS metric1_score,
    qm.ViewCount::int AS metric2_views,
    qm.AnswerCount::int AS metric3_answers,
    qm.tag_count::int AS metric4_tagcount,
    qm.comment_count::int AS metric5_comments,
    qm.top_answerer_name::text AS extra_1,
    qm.hours_to_accept::numeric(10,2) AS extra_2,
    qm.title_body_category AS extra_3
  FROM question_trends qm
  ORDER BY qm.Score DESC NULLS LAST, qm.ViewCount DESC NULLS LAST
  LIMIT 200
),
top_tags_cast AS (
  SELECT
    'tag'::text AS entity_type,
    row_number() OVER (ORDER BY ts.question_count DESC) :: text AS entity_id,
    ts.tag::text AS entity_name,
    ts.question_count::int AS metric1_score,
    round(ts.avg_question_score::numeric,2) AS metric2_views,
    ts.max_views::int AS metric3_answers,
    ts.total_answer_count::int AS metric4_tagcount,
    NULL::int AS metric5_comments,
    NULL::text AS extra_1,
    NULL::numeric(10,2) AS extra_2,
    NULL::text AS extra_3
  FROM tag_stats ts
  ORDER BY ts.question_count DESC
  LIMIT 200
),
top_actors_cast AS (
  SELECT
    'actor'::text AS entity_type,
    ta.user_id::text AS entity_id,
    ta.DisplayName::text AS entity_name,
    ta.top3_answers_count::int AS metric1_score,
    round(ta.avg_top_answer_score::numeric,2) AS metric2_views,
    ta.max_top_answer_score::int AS metric3_answers,
    ta.badge_score::int AS metric4_tagcount,
    ta.gold::int AS metric5_comments,
    ta.silver::text AS extra_1,
    ta.bronze::numeric(10,2) AS extra_2,
    NULL::text AS extra_3
  FROM top_actors ta
  ORDER BY ta.top3_answers_count DESC, ta.avg_top_answer_score DESC
  LIMIT 200
)
-- final unioned output: combines different entity types for mixed-scenario benchmarking
SELECT * FROM top_questions
UNION ALL
SELECT * FROM top_tags_cast
UNION ALL
SELECT * FROM top_actors_cast
ORDER BY entity_type, metric1_score DESC, metric2_views DESC;