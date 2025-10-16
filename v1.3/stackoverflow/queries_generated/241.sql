-- {"query": "241.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4691} 
WITH
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '365 days'
),
question_tags AS (
  SELECT q.id AS question_id,
         q.OwnerUserId,
         q.Score,
         q.CreationDate,
         regexp_split_to_table(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') AS tag
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.Tags IS NOT NULL
),
tag_stats AS (
  SELECT tag,
         count(*) AS question_count,
         avg(score) AS avg_q_score
  FROM question_tags
  GROUP BY tag
),
user_posts AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         count(p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS total_posts,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
         avg(p.Score) AS avg_score,
         max(p.CreationDate) AS last_post_date,
         sum(coalesce(p.ViewCount,0)) AS total_views
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
user_badges AS (
  SELECT b.UserId,
         count(*) AS badge_count,
         count(*) FILTER (WHERE b.Class = 1) AS gold,
         count(*) FILTER (WHERE b.Class = 2) AS silver,
         count(*) FILTER (WHERE b.Class = 3) AS bronze
  FROM Badges b
  GROUP BY b.UserId
),
top_users AS (
  SELECT up.user_id,
         up.DisplayName,
         up.total_posts,
         up.questions,
         up.answers,
         up.avg_score,
         up.total_views,
         coalesce(ub.badge_count,0) AS badge_count,
         coalesce(ub.gold,0) AS gold,
         coalesce(ub.silver,0) AS silver,
         coalesce(ub.bronze,0) AS bronze,
         rank() OVER (ORDER BY coalesce(up.total_posts,0) DESC, coalesce(ub.gold,0) DESC) AS activity_rank
  FROM user_posts up
  LEFT JOIN user_badges ub ON ub.UserId = up.user_id
),
top_posts AS (
  SELECT p.*,
         row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
user_top_posts AS (
  SELECT tp.OwnerUserId AS user_id,
         json_agg(json_build_object('post_id', tp.Id,
                                    'type', tp.PostTypeId,
                                    'score', tp.Score,
                                    'views', tp.ViewCount,
                                    'title', left(coalesce(tp.Title,''),120)
                                   ) ORDER BY tp.Score DESC NULLS LAST, tp.ViewCount DESC NULLS LAST) AS top_posts
  FROM top_posts tp
  WHERE tp.rn <= 3
  GROUP BY tp.OwnerUserId
),
question_answer_times AS (
  SELECT q.Id AS question_id,
         q.OwnerUserId,
         q.CreationDate AS q_created,
         (SELECT min(a.CreationDate - q.CreationDate)
            FROM Posts a
           WHERE a.ParentId = q.Id
             AND a.PostTypeId = 2
             AND a.CreationDate > q.CreationDate
         ) AS time_to_first_answer,
         (SELECT count(distinct a.OwnerUserId)
            FROM Posts a
           WHERE a.ParentId = q.Id
             AND a.PostTypeId = 2
         ) AS distinct_answerers,
         coalesce(q.AnswerCount,
                  (SELECT count(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2)
         ) AS answer_count
  FROM Posts q
  WHERE q.PostTypeId = 1
),
user_question_metrics AS (
  SELECT u.Id AS user_id,
         count(q.question_id) AS asked_questions,
         avg(extract(epoch from q.time_to_first_answer)) AS avg_seconds_to_first_answer,
         avg(q.answer_count) AS avg_answers_per_question,
         avg(q.distinct_answerers) AS avg_distinct_answerers
  FROM Users u
  LEFT JOIN question_answer_times q ON q.OwnerUserId = u.Id
  GROUP BY u.Id
),
active_or_highrep AS (
  SELECT user_id FROM top_users WHERE total_posts >= 50
  UNION
  SELECT Id AS user_id FROM Users WHERE Reputation >= 20000
),
final_users AS (
  SELECT tu.user_id,
         tu.DisplayName,
         coalesce(tu.total_posts,0) AS total_posts,
         coalesce(tu.questions,0) AS questions,
         coalesce(tu.answers,0) AS answers,
         coalesce(tu.avg_score,0) AS avg_score,
         coalesce(tu.total_views,0) AS total_views,
         coalesce(ub.badge_count,0) AS badge_count,
         coalesce(ub.gold,0) AS gold,
         coalesce(ub.silver,0) AS silver,
         coalesce(ub.bronze,0) AS bronze,
         coalesce(utp.top_posts, '[]'::json) AS top_posts,
         uqm.asked_questions,
         uqm.avg_seconds_to_first_answer,
         uqm.avg_answers_per_question,
         uqm.avg_distinct_answerers
  FROM top_users tu
  FULL OUTER JOIN user_badges ub ON ub.UserId = tu.user_id
  FULL OUTER JOIN user_top_posts utp ON utp.user_id = tu.user_id
  FULL OUTER JOIN user_question_metrics uqm ON uqm.user_id = tu.user_id
  WHERE tu.user_id IN (SELECT user_id FROM active_or_highrep)
     OR ub.UserId   IN (SELECT user_id FROM active_or_highrep)
     OR utp.user_id IN (SELECT user_id FROM active_or_highrep)
)
SELECT fu.user_id,
       fu.DisplayName,
       fu.total_posts,
       fu.questions,
       fu.answers,
       round(coalesce(fu.avg_score,0)::numeric,2) AS avg_score,
       CASE WHEN fu.total_posts > 0 THEN round(fu.total_views::numeric / greatest(fu.total_posts,1),2) ELSE NULL END AS avg_views_per_post,
       fu.badge_count,
       fu.gold,
       fu.silver,
       fu.bronze,
       coalesce(fu.asked_questions,0) AS asked_questions,
       CASE WHEN fu.avg_seconds_to_first_answer IS NULL THEN NULL ELSE (round(fu.avg_seconds_to_first_answer) || ' seconds') END AS avg_time_to_first_answer,
       round(coalesce(fu.avg_answers_per_question,0)::numeric,2) AS avg_answers_per_question,
       round(coalesce(fu.avg_distinct_answerers,0)::numeric,2) AS avg_distinct_answerers,
       (SELECT count(*) FROM Comments c WHERE c.UserId = fu.user_id AND c.CreationDate > now() - interval '365 days') AS recent_comments,
       (
         SELECT string_agg(t.tag, ',') FROM (
           SELECT qt.tag, count(*) AS cnt
           FROM question_tags qt
           WHERE qt.OwnerUserId = fu.user_id
           GROUP BY qt.tag
           ORDER BY cnt DESC, qt.tag
           LIMIT 5
         ) t
       ) AS top_user_tags,
       CASE
         WHEN fu.gold > 0 THEN 'Gold+'
         WHEN fu.silver > 0 THEN 'SilverOnly'
         WHEN fu.bronze > 10 THEN 'BronzeCollector'
         ELSE 'Normal'
       END AS badge_profile,
       fu.top_posts
FROM final_users fu
LEFT JOIN Users u ON u.Id = fu.user_id
WHERE fu.user_id IS NOT NULL
  AND (fu.total_posts IS NOT NULL OR fu.badge_count > 0)
ORDER BY fu.total_posts DESC NULLS LAST, fu.gold DESC NULLS LAST, fu.user_id
LIMIT 200;