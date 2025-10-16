-- {"query": "372.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12567} 
WITH
posts_q AS (
  SELECT * FROM Posts WHERE PostTypeId = 1
),
posts_a AS (
  SELECT * FROM Posts WHERE PostTypeId = 2
),
tags_exploded AS (
  SELECT
    q.Id AS QuestionId,
    lower(trim(t.tag)) AS Tag
  FROM posts_q q
  CROSS JOIN LATERAL regexp_split_to_table(
    substring(q.Tags from 2 for char_length(q.Tags)-2),
    '><'
  ) AS t(tag)
  WHERE q.Tags IS NOT NULL AND char_length(q.Tags) > 2
),
answer_stats_per_question AS (
  SELECT
    q.Id AS QuestionId,
    COUNT(a.Id) AS answer_count,
    AVG(a.Score)::numeric(12,6) AS avg_answer_score,
    MAX(a.Score) AS max_answer_score,
    MIN(a.Score) AS min_answer_score,
    EXTRACT(EPOCH FROM AVG(a.CreationDate - q.CreationDate)) AS avg_seconds_to_answer,
    EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate)) AS seconds_to_first_answer
  FROM posts_q q
  LEFT JOIN posts_a a ON a.ParentId = q.Id
  GROUP BY q.Id
),
tag_question_agg AS (
  SELECT
    t.Tag,
    COUNT(DISTINCT t.QuestionId) AS total_questions,
    SUM(COALESCE(q.Score,0)) AS sum_score,
    AVG(COALESCE(q.Score,0))::numeric(12,6) AS avg_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY q.Score) AS median_score,
    AVG(COALESCE(q.ViewCount,0))::bigint AS avg_views,
    SUM(CASE WHEN q.ClosedDate IS NULL THEN 1 ELSE 0 END) AS open_questions,
    SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_questions,
    AVG(asq.seconds_to_first_answer) AS avg_seconds_to_first_answer,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY asq.seconds_to_first_answer) AS median_seconds_to_first_answer
  FROM tags_exploded t
  JOIN posts_q q ON q.Id = t.QuestionId
  LEFT JOIN answer_stats_per_question asq ON asq.QuestionId = q.Id
  GROUP BY t.Tag
),
top_answerers_agg AS (
  SELECT
    s.Tag,
    s.UserId,
    s.UserDisplay,
    s.answers,
    s.total_answer_score,
    s.avg_answer_score,
    ROW_NUMBER() OVER (PARTITION BY s.Tag ORDER BY s.total_answer_score DESC, s.answers DESC) AS rn
  FROM (
    SELECT
      te.Tag,
      a.OwnerUserId AS UserId,
      COALESCE(u.DisplayName, '(anon)') AS UserDisplay,
      COUNT(a.Id) AS answers,
      SUM(a.Score) AS total_answer_score,
      AVG(a.Score)::numeric(10,3) AS avg_answer_score
    FROM tags_exploded te
    JOIN posts_a a ON a.ParentId = te.QuestionId
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.OwnerUserId IS NOT NULL
    GROUP BY te.Tag, a.OwnerUserId, u.DisplayName
  ) s
),
top3_answerers AS (
  SELECT
    Tag,
    string_agg(format('%s(%s/%s)', UserDisplay, answers, total_answer_score), ', ' ORDER BY total_answer_score DESC, answers DESC) AS top3
  FROM (
    SELECT Tag, UserDisplay, answers, total_answer_score
    FROM top_answerers_agg
    WHERE rn <= 3
    ORDER BY Tag, total_answer_score DESC, answers DESC
  ) x
  GROUP BY Tag
),
user_badge_tag_count AS (
  SELECT
    b.UserId,
    lower(b.Name) AS badge_name,
    COUNT(*) AS badge_count
  FROM Badges b
  GROUP BY b.UserId, lower(b.Name)
),
top_answerers_with_badges AS (
  SELECT
    t.Tag,
    t.UserId,
    t.UserDisplay,
    t.answers,
    t.total_answer_score,
    COALESCE(ub.badge_count, 0) AS badges_for_tag
  FROM top_answerers_agg t
  LEFT JOIN user_badge_tag_count ub ON ub.UserId = t.UserId AND ub.badge_name = t.Tag
  WHERE t.rn <= 3
),
tag_link_stats AS (
  SELECT
    te.Tag,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_count,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_count
  FROM tags_exploded te
  LEFT JOIN PostLinks pl ON (pl.PostId = te.QuestionId OR pl.RelatedPostId = te.QuestionId)
  GROUP BY te.Tag
),
editor_stats_per_question AS (
  SELECT
    ph.PostId,
    COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS distinct_editors,
    COUNT(ph.Id) AS revisions,
    MAX(ph.CreationDate) AS last_revision
  FROM PostHistory ph
  GROUP BY ph.PostId
),
tag_editor_stats AS (
  SELECT
    te.Tag,
    AVG(COALESCE(es.distinct_editors,0))::numeric(10,3) AS avg_distinct_editors,
    AVG(COALESCE(es.revisions,0))::numeric(10,3) AS avg_revisions,
    MAX(COALESCE(es.last_revision, '1970-01-01'::timestamp)) AS most_recent_revision
  FROM tags_exploded te
  LEFT JOIN editor_stats_per_question es ON es.PostId = te.QuestionId
  GROUP BY te.Tag
),
popular_tags AS (
  SELECT Tag FROM tag_question_agg WHERE total_questions >= 100
),
active_tags AS (
  SELECT Tag FROM tag_question_agg WHERE accepted_questions::float / NULLIF(total_questions,0) >= 0.30
),
popular_active_tags AS (
  SELECT Tag FROM popular_tags INTERSECT SELECT Tag FROM active_tags
),
weird_tags AS (
  SELECT Tag FROM popular_tags
  EXCEPT
  SELECT Tag FROM active_tags
),
sample_tag_union AS (
  SELECT Tag FROM popular_active_tags
  UNION
  SELECT Tag FROM weird_tags
),
tag_rankings AS (
  SELECT
    t.Tag,
    t.total_questions,
    t.sum_score,
    t.avg_score,
    t.median_score,
    t.avg_views,
    t.accepted_questions,
    t.open_questions,
    ROUND(100.0 * t.accepted_questions::numeric / NULLIF(t.total_questions,0),2) AS pct_accepted,
    COALESCE(t.avg_seconds_to_first_answer, -1) AS avg_secs_to_first_answer,
    COALESCE(t.median_seconds_to_first_answer, -1) AS median_secs_to_first_answer,
    COALESCE(l.linked_count,0) AS linked_count,
    COALESCE(l.duplicate_count,0) AS duplicate_count,
    COALESCE(te.avg_distinct_editors,0) AS avg_distinct_editors,
    COALESCE(te.avg_revisions,0) AS avg_revisions,
    COALESCE(te.most_recent_revision, '1970-01-01'::timestamp) AS most_recent_revision,
    COALESCE(top3.top3, '(no answers)') AS top3_answerers,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM posts_q p JOIN tags_exploded tx ON tx.QuestionId = p.Id WHERE tx.Tag = t.Tag AND p.OwnerUserId IS NOT NULL) AS distinct_askers
  FROM tag_question_agg t
  LEFT JOIN tag_link_stats l ON l.Tag = t.Tag
  LEFT JOIN tag_editor_stats te ON te.Tag = t.Tag
  LEFT JOIN top3_answerers top3 ON top3.Tag = t.Tag
),
tag_final AS (
  SELECT
    tr.*,
    dense_rank() OVER (ORDER BY tr.total_questions DESC) AS rank_by_questions,
    dense_rank() OVER (ORDER BY tr.avg_score DESC NULLS LAST) AS rank_by_avg_score,
    dense_rank() OVER (ORDER BY tr.avg_secs_to_first_answer ASC NULLS LAST) AS rank_by_speed,
    CASE
      WHEN tr.total_questions >= 1000 THEN 'major'
      WHEN tr.total_questions >= 100 THEN 'medium'
      ELSE 'niche'
    END AS tag_popularity_bucket
  FROM tag_rankings tr
),
overall_metrics AS (
  SELECT
    '<<OVERALL-STATS>>'::text AS Tag,
    COUNT(*) FILTER (WHERE PostTypeId = 1) AS total_questions,
    AVG(CASE WHEN PostTypeId = 1 THEN Score END)::numeric(12,4) AS avg_question_score,
    (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) FROM Posts p2 WHERE p2.PostTypeId = 1) AS median_question_score,
    AVG(CASE WHEN PostTypeId = 2 THEN Score END)::numeric(12,4) AS avg_answer_score,
    COUNT(DISTINCT OwnerUserId) FILTER (WHERE PostTypeId = 1) AS distinct_askers,
    COUNT(DISTINCT OwnerUserId) FILTER (WHERE PostTypeId = 2) AS distinct_answerers,
    (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 2) AS total_upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 3) AS total_downvotes
  FROM Posts
)
SELECT
  tf.Tag,
  tf.tag_popularity_bucket,
  tf.rank_by_questions,
  tf.rank_by_avg_score,
  tf.rank_by_speed,
  tf.total_questions,
  tf.distinct_askers,
  tf.avg_score,
  tf.median_score,
  tf.avg_views,
  tf.pct_accepted,
  CASE
    WHEN tf.avg_secs_to_first_answer <= 0 THEN '(no data)'
    ELSE to_char((timestamp 'epoch' + make_interval(secs => ROUND(tf.avg_secs_to_first_answer)))::time, 'HH24:MI:SS')
  END AS avg_time_to_first_answer,
  CASE
    WHEN tf.median_secs_to_first_answer <= 0 THEN '(no data)'
    ELSE to_char((timestamp 'epoch' + make_interval(secs => ROUND(tf.median_secs_to_first_answer)))::time, 'HH24:MI:SS')
  END AS median_time_to_first_answer,
  tf.top3_answerers,
  tf.linked_count,
  tf.duplicate_count,
  tf.avg_distinct_editors,
  tf.avg_revisions,
  tf.most_recent_revision,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId IN (SELECT QuestionId FROM tags_exploded te2 WHERE te2.Tag = tf.Tag)) AS comment_count_on_tag_questions,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT QuestionId FROM tags_exploded te3 WHERE te3.Tag = tf.Tag) AND v.VoteTypeId = 2) AS upvotes_on_tag_questions,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT QuestionId FROM tags_exploded te4 WHERE te4.Tag = tf.Tag) AND v.VoteTypeId = 3) AS downvotes_on_tag_questions,
  COALESCE(o.total_questions,0) AS overall_total_questions,
  o.avg_question_score,
  o.median_question_score,
  o.avg_answer_score,
  CASE
    WHEN tf.total_questions = 0 THEN '(no questions)'
    WHEN tf.pct_accepted IS NULL THEN '(no accepted data)'
    WHEN tf.pct_accepted >= 50 THEN 'healthy'
    WHEN tf.pct_accepted >= 20 THEN 'questionable'
    ELSE 'low-accept-rate'
  END AS health,
  COALESCE(NULLIF(tf.Tag, ''), '(unknown)') || ' | ' || initcap(replace(tf.Tag,'-',' ')) AS tag_label,
  CASE WHEN tf.Tag IN (SELECT Tag FROM sample_tag_union) THEN true ELSE false END AS in_sample_union
FROM tag_final tf
FULL OUTER JOIN overall_metrics o ON true
WHERE tf.Tag IN (SELECT Tag FROM sample_tag_union)
ORDER BY tf.rank_by_questions ASC, tf.avg_score DESC
LIMIT 200;