-- {"query": "232.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5449} 
WITH
recent_posts AS (
  SELECT p.*,
    CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><') ELSE NULL END AS tag_array
  FROM Posts p
),
exploded_tags AS (
  SELECT p.Id AS PostId, unnest(p.tag_array) AS tag
  FROM recent_posts p
  WHERE p.tag_array IS NOT NULL
),
tag_metrics AS (
  SELECT et.tag,
    count(*) AS q_count,
    avg(p.AnswerCount::numeric) FILTER (WHERE p.AnswerCount IS NOT NULL) AS avg_answers,
    avg(p.Score::numeric) AS avg_score,
    max(p.ViewCount) AS max_views,
    percentile_disc(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
  FROM exploded_tags et
  JOIN Posts p ON p.Id = et.PostId
  GROUP BY et.tag
),
user_base AS (
  SELECT u.*,
    COALESCE(u.DisplayName,'<deleted>') AS display,
    COALESCE(u.Location,'') AS loc,
    (SELECT count(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS q_count,
    (SELECT count(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS a_count,
    (SELECT avg(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS avg_post_score,
    (SELECT count(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS up_votes_cast,
    (SELECT count(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS down_votes_cast
  FROM Users u
  WHERE u.Reputation > 0
),
badge_summary AS (
  SELECT UserId,
    sum(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS gold,
    sum(CASE WHEN Class=2 THEN 1 ELSE 0 END) AS silver,
    sum(CASE WHEN Class=3 THEN 1 ELSE 0 END) AS bronze,
    max(Date) AS last_badge_date,
    max(Name) FILTER (WHERE Date = (SELECT max(b2.Date) FROM Badges b2 WHERE b2.UserId = Badges.UserId)) AS last_badge_name
  FROM Badges
  GROUP BY UserId
),
user_tag_affinity AS (
  SELECT ub.Id AS UserId, et.tag,
    count(*) AS posts_with_tag,
    sum(COALESCE(p.Score,0)) AS tag_score,
    row_number() OVER (PARTITION BY ub.Id ORDER BY count(*) DESC, sum(COALESCE(p.Score,0)) DESC) AS rn
  FROM user_base ub
  JOIN Posts p ON p.OwnerUserId = ub.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
  ) AS et(tag) ON p.PostTypeId = 1 AND p.Tags IS NOT NULL
  WHERE p.PostTypeId IN (1,2)
  GROUP BY ub.Id, et.tag
),
top_tag_per_user AS (
  SELECT UserId, tag, posts_with_tag, tag_score
  FROM user_tag_affinity
  WHERE rn = 1
),
answer_analysis AS (
  SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.OwnerUserId AS AnswererId, a.Score AS AnswerScore,
    q.Score AS QuestionScore, q.Tags, q.Title,
    (SELECT count(*) FROM Comments c WHERE c.PostId = a.Id) AS comments_on_answer,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS upvotes_on_answer,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS upvotes_on_question
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
),
user_rankings AS (
  SELECT ub.Id,
    ub.display, ub.Reputation, ub.CreationDate,
    COALESCE(ub.q_count,0) AS questions,
    COALESCE(ub.a_count,0) AS answers,
    COALESCE(ub.avg_post_score,0) AS avg_score,
    COALESCE(b.gold,0) AS gold, COALESCE(b.silver,0) AS silver, COALESCE(b.bronze,0) AS bronze,
    COALESCE(tb.tag,'<none>') AS top_tag,
    COALESCE(tb.posts_with_tag,0) AS top_tag_posts,
    rank() OVER (ORDER BY ub.Reputation DESC, COALESCE(ub.a_count,0) DESC) AS global_rank,
    dense_rank() OVER (PARTITION BY COALESCE(tb.tag,'<none>') ORDER BY ub.Reputation DESC) AS tag_rank
  FROM user_base ub
  LEFT JOIN badge_summary b ON b.UserId = ub.Id
  LEFT JOIN top_tag_per_user tb ON tb.UserId = ub.Id
),
combined_tags AS (
  SELECT tag AS t FROM tag_metrics
  UNION
  SELECT TagName FROM Tags WHERE TagName IS NOT NULL
),
tag_full AS (
  SELECT ct.t AS tag,
    tm.q_count, tm.avg_answers, tm.avg_score, tm.max_views, tm.median_score,
    COALESCE(tg.Count,0) AS global_count,
    (SELECT p.Id FROM Posts p
     WHERE p.PostTypeId=1 AND p.Tags IS NOT NULL
       AND EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS x(tg2) WHERE x.tg2 = ct.t)
     ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST
     LIMIT 1) AS sample_post_id
  FROM combined_tags ct
  LEFT JOIN tag_metrics tm ON tm.tag = ct.t
  LEFT JOIN Tags tg ON tg.TagName = ct.t
),
final AS (
  SELECT ur.Id AS user_id,
    ur.display,
    ur.Reputation,
    ur.questions, ur.answers, ur.avg_score,
    ur.gold, ur.silver, ur.bronze,
    ur.top_tag, ur.top_tag_posts,
    ur.global_rank, ur.tag_rank,
    (COALESCE(ur.Reputation::numeric,0) * 0.5 + COALESCE(ur.answers,0) * 10 + (COALESCE(ur.gold,0)*50 + COALESCE(ur.silver,0)*20 + COALESCE(ur.bronze,0)*5))::numeric AS engagement_score,
    (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY (next_date - prev_date))
     FROM (
       SELECT lag(CreationDate) OVER (ORDER BY CreationDate) AS prev_date, CreationDate AS next_date
       FROM Posts p2 WHERE p2.OwnerUserId = ur.Id AND p2.CreationDate IS NOT NULL
     ) dif WHERE prev_date IS NOT NULL) AS median_interpost_interval,
    (SELECT avg(aa.AnswerScore) FROM answer_analysis aa WHERE aa.AnswererId = ur.Id) AS avg_answer_score,
    NULLIF( (SELECT count(*) FROM Posts p3 WHERE p3.OwnerUserId = ur.Id AND p3.PostTypeId=1), 0) AS question_count_nonnull
  FROM user_rankings ur
),
synthetic_union AS (
  SELECT 'A' AS source, t.tag, COALESCE(t.q_count,0) AS q_count FROM tag_full t WHERE t.q_count IS NOT NULL AND t.q_count > 10
  UNION
  SELECT 'B' AS source, TagName AS tag, Count AS q_count FROM Tags WHERE Count > 10
  EXCEPT
  SELECT 'C' AS source, 'ignore' AS tag, 0 AS q_count WHERE false
)
SELECT f.user_id,
 f.display,
 f.Reputation,
 f.questions, f.answers,
 f.avg_score,
 f.gold, f.silver, f.bronze,
 f.top_tag,
 f.top_tag_posts,
 f.global_rank,
 f.tag_rank,
 ROUND(f.engagement_score,2) AS engagement_score,
 COALESCE((f.median_interpost_interval)::text,'n/a') AS median_interpost_interval,
 COALESCE(ROUND(f.avg_answer_score::numeric,2),'0') AS avg_answer_score,
 t.q_count AS top_tag_q_count,
 t.avg_answers AS top_tag_avg_answers,
 t.avg_score AS top_tag_avg_score,
 t.max_views AS top_tag_max_views,
 (SELECT array_agg(sub.Title) FROM (
    SELECT DISTINCT p.Title
    FROM Posts p
    WHERE p.PostTypeId=1 AND p.Tags IS NOT NULL
      AND EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS x(tg) WHERE tg = f.top_tag)
    ORDER BY p.Score DESC NULLS LAST
    LIMIT 5
 ) sub) AS sample_titles,
 su.source IS NOT NULL AS in_synthetic_union,
 CASE WHEN (f.top_tag IS NULL OR f.top_tag = '<none>' OR f.top_tag = '') THEN false
      WHEN lower(f.display) LIKE '%' || lower(COALESCE(f.top_tag,'')) || '%' THEN true
      ELSE EXISTS (SELECT 1 FROM Tags tg2 WHERE tg2.TagName = f.top_tag AND tg2.IsModeratorOnly = 0)
 END AS tag_name_matches_display_or_public
FROM final f
LEFT JOIN tag_full t ON t.tag = f.top_tag
LEFT JOIN synthetic_union su ON su.tag = f.top_tag
WHERE f.Reputation > 100
ORDER BY f.engagement_score DESC NULLS LAST
LIMIT 250;