-- {"query": "357.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12345} 
WITH
questions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags,
    CASE WHEN p.Tags IS NULL THEN '' ELSE substring(p.Tags from 2 for char_length(p.Tags)-2) END AS tags_inner
  FROM Posts p
  WHERE p.PostTypeId = 1
),
question_tags AS (
  SELECT q.*, t.tag
  FROM questions q
  CROSS JOIN LATERAL regexp_split_to_table(q.tags_inner, '><') AS t(tag)
  WHERE q.tags_inner <> ''
),
answers AS (
  SELECT p.*
  FROM Posts p
  WHERE p.PostTypeId = 2
),
first_answer_per_question AS (
  SELECT a.ParentId AS QuestionId, min(a.CreationDate) AS FirstAnswerDate, min(a.Id) AS FirstAnswerId
  FROM answers a
  WHERE a.ParentId IS NOT NULL
  GROUP BY a.ParentId
),
postlink_dup_counts AS (
  SELECT pl.PostId, count(*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_count
  FROM PostLinks pl
  GROUP BY pl.PostId
),
post_activity_summary AS (
  SELECT
    qt.tag,
    count(*)::bigint AS question_count,
    sum(coalesce(qt.ViewCount,0))::bigint AS views,
    sum(CASE WHEN qt.Score > 0 THEN 1 ELSE 0 END) AS positive_scores,
    avg(coalesce(qt.Score,0))::numeric AS avg_score,
    avg(coalesce(qt.AnswerCount,0))::numeric AS avg_answer_count,
    avg( extract(epoch FROM (coalesce(fa.FirstAnswerDate, qt.CreationDate) - qt.CreationDate)) / 3600 )::numeric AS avg_hours_to_first_answer,
    sum(coalesce(pl.duplicate_count,0))::bigint AS duplicate_links
  FROM question_tags qt
  LEFT JOIN first_answer_per_question fa ON fa.QuestionId = qt.Id
  LEFT JOIN postlink_dup_counts pl ON pl.PostId = qt.Id
  GROUP BY qt.tag
),
tag_badge_impact AS (
  -- intentionally heavy correlated-subquery aggregation: counts of badges among askers for each tag
  SELECT
    qt.tag,
    count(DISTINCT qt.OwnerUserId) FILTER (WHERE EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = qt.OwnerUserId))::bigint AS badge_users,
    sum((SELECT count(*) FROM Badges b WHERE b.UserId = qt.OwnerUserId AND b.Class = 1))::bigint AS golds,
    sum((SELECT count(*) FROM Badges b WHERE b.UserId = qt.OwnerUserId AND b.Class = 2))::bigint AS silvers,
    sum((SELECT count(*) FROM Badges b WHERE b.UserId = qt.OwnerUserId AND b.Class = 3))::bigint AS bronzes
  FROM question_tags qt
  GROUP BY qt.tag
),
top_answerers_per_tag AS (
  SELECT t.tag,
         a.OwnerUserId AS UserId,
         count(*)::bigint AS answers_count,
         sum(coalesce(a.Score,0))::bigint AS answers_score,
         avg( extract(epoch FROM (a.CreationDate - q.CreationDate)) / 3600 )::numeric AS avg_hours_to_answer,
         row_number() OVER (PARTITION BY t.tag ORDER BY count(*) DESC, sum(coalesce(a.Score,0)) DESC NULLS LAST) AS rn
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
  CROSS JOIN LATERAL regexp_split_to_table(CASE WHEN q.Tags IS NULL THEN '' ELSE substring(q.Tags from 2 for char_length(q.Tags)-2) END, '><') AS t(tag)
  WHERE a.PostTypeId = 2
  GROUP BY t.tag, a.OwnerUserId, q.CreationDate
),
tag_top_k AS (
  SELECT tag, UserId, answers_count, answers_score, avg_hours_to_answer
  FROM top_answerers_per_tag
  WHERE rn <= 3
),
user_influence AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         u.Reputation,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1)::int AS questions_asked,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2)::int AS answers_posted,
         sum(coalesce(p.Score,0))::int AS total_score,
         dense_rank() OVER (ORDER BY sum(coalesce(p.Score,0)) DESC) AS score_rank,
         rank() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS reputation_rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
top_tags AS (
  SELECT tag FROM (
    SELECT tag, row_number() OVER (ORDER BY question_count DESC NULLS LAST, views DESC NULLS LAST) AS rn
    FROM post_activity_summary
  ) x
  WHERE rn <= 50
  INTERSECT
  SELECT TagName FROM Tags
),
tag_leaderboard AS (
  SELECT
    ps.tag,
    row_number() OVER (ORDER BY ps.question_count DESC, ps.views DESC) AS tag_popularity_rank,
    ps.question_count,
    ps.views,
    (ps.views::numeric / NULLIF(ps.question_count,0))::numeric AS avg_views_per_question,
    ps.avg_score,
    ps.avg_answer_count,
    ps.avg_hours_to_first_answer,
    ps.duplicate_links
  FROM post_activity_summary ps
  WHERE ps.tag IN (SELECT tag FROM top_tags)
),
per_tag_detail AS (
  SELECT
    tl.tag::text,
    tl.tag_popularity_rank::int,
    tl.question_count::bigint,
    tl.views::bigint,
    round(tl.avg_views_per_question::numeric,3) AS avg_views_per_question,
    round(tl.avg_score::numeric,3) AS avg_score,
    round(tl.avg_answer_count::numeric,3) AS avg_answers,
    round(tl.avg_hours_to_first_answer::numeric,3) AS avg_hours_to_first_answer,
    tl.duplicate_links::bigint,
    coalesce(tbi.golds,0)::bigint AS badge_golds,
    coalesce(tbi.silvers,0)::bigint AS badge_silvers,
    coalesce(tbi.bronzes,0)::bigint AS badge_bronzes,
    (SELECT json_agg(json_build_object(
               'user_id', tt.UserId,
               'answers', tt.answers_count,
               'score', tt.answers_score,
               'avg_hours_to_answer', round(tt.avg_hours_to_answer::numeric,3)
             ) ORDER BY tt.answers_count DESC)
     FROM tag_top_k tt WHERE tt.tag = tl.tag) AS top_answerers_json,
    (SELECT count(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags ILIKE ('%<'||tl.tag||'>%'))::bigint AS exact_tag_match_questions,
    (SELECT count(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM Posts WHERE Tags ILIKE ('%<'||tl.tag||'>%')) AND ph.PostHistoryTypeId = 52)::bigint AS hot_history_count,
    CASE
      WHEN tl.avg_hours_to_first_answer IS NULL THEN 'no-answers'
      WHEN tl.avg_hours_to_first_answer < 1 THEN 'fast'
      WHEN tl.avg_hours_to_first_answer < 24 THEN 'moderate'
      ELSE 'slow'
    END AS responsiveness_class
  FROM tag_leaderboard tl
  LEFT JOIN tag_badge_impact tbi ON tbi.tag = tl.tag
),
global_summary AS (
  SELECT
    '<<GLOBAL>>'::text AS tag,
    0::int AS tag_popularity_rank,
    sum(question_count)::bigint AS question_count,
    sum(views)::bigint AS views,
    round((sum(views)::numeric / NULLIF(sum(question_count),0)),3) AS avg_views_per_question,
    round(avg(avg_score)::numeric,3) AS avg_score,
    round(avg(avg_answer_count)::numeric,3) AS avg_answers,
    round(avg(avg_hours_to_first_answer)::numeric,3) AS avg_hours_to_first_answer,
    sum(duplicate_links)::bigint AS duplicate_links,
    (SELECT count(*) FROM Badges b WHERE b.Class = 1)::bigint AS badge_golds,
    (SELECT count(*) FROM Badges b WHERE b.Class = 2)::bigint AS badge_silvers,
    (SELECT count(*) FROM Badges b WHERE b.Class = 3)::bigint AS badge_bronzes,
    NULL::json AS top_answerers_json,
    NULL::bigint AS exact_tag_match_questions,
    (SELECT count(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 52)::bigint AS hot_history_count,
    'global'::text AS responsiveness_class
  FROM post_activity_summary
)
SELECT *
FROM per_tag_detail
UNION ALL
SELECT * FROM global_summary
ORDER BY CASE WHEN tag = '<<GLOBAL>>' THEN 1 ELSE 0 END, tag_popularity_rank
LIMIT 1000;