-- {"query": "258.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4879} 
WITH recent_questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.Tags,
    CASE
      WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::varchar[]
      ELSE string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')
    END AS tag_array,
    p.Score,
    p.ViewCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
tag_expansion AS (
  SELECT rq.Id, rq.Title, rq.CreationDate, rq.OwnerUserId, rq.AcceptedAnswerId, rq.Tags, unnest(rq.tag_array) AS tag
  FROM recent_questions rq
),
answer_stats AS (
  SELECT
    q.Id AS QuestionId,
    count(a.Id) FILTER (WHERE a.Id IS NOT NULL) AS total_answers,
    avg(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS avg_answer_score,
    max(a.Score) AS max_answer_score,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) AS has_accepted_present
  FROM recent_questions q
  LEFT JOIN Posts a ON a.ParentId = q.Id
  GROUP BY q.Id
),
activity AS (
  SELECT
    ph.PostId,
    count(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)) AS substantive_edits,
    count(*) AS history_events,
    max(ph.CreationDate) AS last_history_date,
    min(ph.CreationDate) AS first_history_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
vote_breakdown AS (
  SELECT
    v.PostId,
    count(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
    count(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
    count(*) FILTER (WHERE v.VoteTypeId = 1) AS accepted_votes,
    count(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
top_contributors AS (
  SELECT
    q.Id AS QuestionId,
    a.OwnerUserId AS TopAnswererId,
    a.Id AS TopAnswerId,
    a.Score,
    row_number() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rn
  FROM recent_questions q
  LEFT JOIN Posts a ON a.ParentId = q.Id
  WHERE a.OwnerUserId IS NOT NULL
),
top_answers AS (
  SELECT QuestionId, TopAnswererId, TopAnswerId, Score
  FROM top_contributors
  WHERE rn = 1
),
user_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    count(b.Id) AS badges_total,
    sum(case when b.Class = 1 then 1 else 0 end) AS gold_badges,
    sum(case when b.Class = 2 then 1 else 0 end) AS silver_badges,
    sum(case when b.Class = 3 then 1 else 0 end) AS bronze_badges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
correlated AS (
  SELECT
    q.Id AS QuestionId,
    (SELECT EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))::bigint
     FROM Posts a
     WHERE a.Id = q.AcceptedAnswerId AND a.CreationDate IS NOT NULL
     LIMIT 1) AS seconds_to_accept,
    (SELECT count(*) FROM Comments c WHERE c.PostId = q.Id) AS comment_count,
    (SELECT count(*) FROM Posts a2 WHERE a2.ParentId = q.Id AND a2.Score >= q.Score) AS answers_with_score_geq_question
  FROM recent_questions q
),
combined AS (
  SELECT
    q.Id AS question_id,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    coalesce(q.AnswerCount, 0) AS declared_answer_count,
    coalesce(a_stats.total_answers, 0) AS computed_answer_count,
    coalesce(a_stats.avg_answer_score, 0) AS avg_answer_score,
    coalesce(a_stats.max_answer_score, 0) AS max_answer_score,
    coalesce(vb.upvotes, 0) AS q_upvotes,
    coalesce(vb.downvotes, 0) AS q_downvotes,
    coalesce(act.substantive_edits, 0) AS substantive_edits,
    coalesce(act.history_events, 0) AS history_events,
    coalesce(cor.seconds_to_accept, -1) AS seconds_to_accept,
    coalesce(cor.comment_count, 0) AS comment_count,
    ta.TopAnswerId,
    ta.TopAnswererId,
    ta.Score AS top_answer_score,
    u.DisplayName AS top_answerer_name,
    us.badges_total AS top_answerer_badges,
    us.reputation AS top_answerer_reputation,
    te.tag
  FROM recent_questions q
  LEFT JOIN answer_stats a_stats ON a_stats.QuestionId = q.Id
  LEFT JOIN activity act ON act.PostId = q.Id
  LEFT JOIN vote_breakdown vb ON vb.PostId = q.Id
  LEFT JOIN top_answers ta ON ta.QuestionId = q.Id
  LEFT JOIN Users u ON u.Id = ta.TopAnswererId
  LEFT JOIN user_stats us ON us.UserId = ta.TopAnswererId
  LEFT JOIN tag_expansion te ON te.Id = q.Id
  LEFT JOIN correlated cor ON cor.QuestionId = q.Id
),
ranked AS (
  SELECT
    *,
    row_number() OVER (PARTITION BY tag ORDER BY (computed_answer_count + avg_answer_score * 0.5 + q_upvotes) DESC NULLS LAST) AS tag_rank,
    rank() OVER (ORDER BY (computed_answer_count + avg_answer_score + q_upvotes * 2) DESC) AS global_rank,
    dense_rank() OVER (PARTITION BY date_trunc('month', CreationDate) ORDER BY q_upvotes DESC) AS monthly_popularity_rank
  FROM combined
),
final AS (
  SELECT
    r.*,
    (coalesce(r.computed_answer_count, 0) * 10
     + coalesce(r.avg_answer_score, 0) * 5
     + (case when r.seconds_to_accept >= 0 then greatest(0, 86400 - r.seconds_to_accept) / 8640.0 else 0 end)
     + (case when r.substantive_edits > 0 then ln(r.substantive_edits + 1) else 0 end)
     + (case when r.top_answerer_reputation > 10000 then 50 when r.top_answerer_reputation > 1000 then 20 else coalesce(r.top_answerer_reputation, 0) / 100 end)
    ) AS synthetic_hotness,
    concat(
      coalesce(r.tag, '<untagged>'),
      ':',
      coalesce(nullif(trim(r.Title), ''), '[no title]'),
      ' (', coalesce(r.TopAnswerId::text, 'NA'), ')'
    ) AS brief_repr,
    (case when r.seconds_to_accept >= 0 and r.seconds_to_accept < 86400 then true else false end) AS accepted_within_day
  FROM ranked r
)
SELECT
  f.question_id,
  f.Title,
  f.tag,
  f.CreationDate,
  f.declared_answer_count,
  f.computed_answer_count,
  f.avg_answer_score,
  f.max_answer_score,
  f.q_upvotes,
  f.q_downvotes,
  f.comment_count,
  f.substantive_edits,
  f.seconds_to_accept,
  f.accepted_within_day,
  f.TopAnswerId,
  f.TopAnswererId,
  f.top_answerer_name,
  f.top_answerer_reputation,
  f.top_answerer_badges,
  f.synthetic_hotness,
  f.brief_repr,
  lag(f.synthetic_hotness) OVER (PARTITION BY f.tag ORDER BY f.synthetic_hotness DESC) AS prev_hotness_in_tag,
  lead(f.synthetic_hotness) OVER (PARTITION BY f.tag ORDER BY f.synthetic_hotness DESC) AS next_hotness_in_tag,
  (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = f.question_id AND pl.LinkTypeId = 3) AS duplicate_count,
  EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = f.question_id AND a.OwnerUserId = f.OwnerUserId) AS self_answered,
  (SELECT count(*) FROM (
     SELECT TagName FROM Tags WHERE TagName = f.tag
     UNION
     SELECT TagName FROM Tags WHERE TagName ILIKE f.tag || '%' LIMIT 1
   ) s) AS related_tag_names
FROM final f
WHERE f.computed_answer_count >= 1
  AND (f.q_upvotes - f.q_downvotes) >= 0
ORDER BY f.synthetic_hotness DESC
LIMIT 200;