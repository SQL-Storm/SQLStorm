WITH recent_users AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    u.reputation,
    u.creationdate
  FROM users u
  WHERE u.creationdate >= (
    SELECT MAX(creationdate) - INTERVAL '365 days'
    FROM users
  )
),
question_posts AS (
  SELECT
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.tags,
    p.title
  FROM posts p
  WHERE p.posttypeid = 1
),
answer_posts AS (
  SELECT
    p.id,
    p.parentid,
    p.owneruserid,
    p.creationdate,
    p.score
  FROM posts p
  WHERE p.posttypeid = 2
),
q_activity AS (
  SELECT
    q.id AS question_id,
    q.owneruserid AS asker_id,
    COALESCE(q.score, 0) AS q_score,
    COALESCE(q.viewcount, 0) AS q_views,
    COALESCE(q.answercount, 0) AS q_answers,
    q.creationdate AS q_created,
    q.tags,
    q.title,
    COUNT(DISTINCT c.id) AS comment_count,
    COUNT(DISTINCT v_up.id) FILTER (WHERE v_up.votetypeid = 2) AS q_upvotes,
    COUNT(DISTINCT v_dn.id) FILTER (WHERE v_dn.votetypeid = 3) AS q_downvotes
  FROM question_posts q
  LEFT JOIN comments c ON c.postid = q.id
  LEFT JOIN votes v_up ON v_up.postid = q.id AND v_up.votetypeid = 2
  LEFT JOIN votes v_dn ON v_dn.postid = q.id AND v_dn.votetypeid = 3
  GROUP BY
    q.id,
    q.owneruserid,
    q.score,
    q.viewcount,
    q.answercount,
    q.creationdate,
    q.tags,
    q.title
),
a_activity AS (
  SELECT
    a.parentid AS question_id,
    COUNT(*) AS answers_total,
    COUNT(*) FILTER (WHERE a.score >= 1) AS answers_positive,
    COUNT(*) FILTER (WHERE a.score < 0) AS answers_negative,
    MAX(a.score) AS best_answer_score,
    MIN(a.score) AS worst_answer_score,
    COUNT(DISTINCT a.owneruserid) AS unique_answerers
  FROM answer_posts a
  GROUP BY a.parentid
),
q_links AS (
  SELECT
    pl.postid AS question_id,
    COUNT(*) FILTER (WHERE pl.linktypeid = 1) AS links_linked,
    COUNT(*) FILTER (WHERE pl.linktypeid = 3) AS links_duplicates
  FROM postlinks pl
  GROUP BY pl.postid
),
q_edits AS (
  SELECT
    ph.postid AS question_id,
    COUNT(*) FILTER (WHERE ph.posthistorytypeid IN (4, 5, 6, 7, 8, 9)) AS edit_events,
    MAX(ph.creationdate) AS last_edit_date
  FROM posthistory ph
  GROUP BY ph.postid
),
q_favorites AS (
  SELECT
    v.postid AS question_id,
    COUNT(*) FILTER (WHERE v.votetypeid = 5) AS favorites
  FROM votes v
  GROUP BY v.postid
),
tag_expansion AS (
  SELECT
    q.id AS question_id,
    UNNEST(string_to_array(SUBSTRING(q.tags FROM 2 FOR CHAR_LENGTH(q.tags) - 2), '><')) AS tag
  FROM question_posts q
  WHERE q.tags IS NOT NULL AND q.tags LIKE '<%'
),
tag_stats AS (
  SELECT
    te.question_id,
    COUNT(*) AS tag_count,
    ARRAY_AGG(te.tag ORDER BY te.tag) AS tag_list
  FROM tag_expansion te
  GROUP BY te.question_id
),
user_recentness AS (
  SELECT
    u.id AS user_id,
    CASE
      WHEN u.creationdate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days' THEN 'new_30d'
      WHEN u.creationdate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days' THEN 'new_90d'
      WHEN u.creationdate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days' THEN 'new_180d'
      WHEN u.creationdate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days' THEN 'new_365d'
      ELSE 'older'
    END AS cohort
  FROM users u
),
hot_candidates AS (
  SELECT
    qa.question_id,
    qa.asker_id,
    qa.q_score,
    qa.q_views,
    qa.q_answers,
    qa.q_created,
    qa.tags,
    qa.title,
    qa.comment_count,
    qa.q_upvotes,
    qa.q_downvotes,
    COALESCE(aa.answers_total, 0) AS answers_total,
    COALESCE(aa.answers_positive, 0) AS answers_positive,
    COALESCE(aa.answers_negative, 0) AS answers_negative,
    COALESCE(aa.best_answer_score, 0) AS best_answer_score,
    COALESCE(aa.worst_answer_score, 0) AS worst_answer_score,
    COALESCE(aa.unique_answerers, 0) AS unique_answerers,
    COALESCE(ql.links_linked, 0) AS links_linked,
    COALESCE(ql.links_duplicates, 0) AS links_duplicates,
    COALESCE(qe.edit_events, 0) AS edit_events,
    qe.last_edit_date,
    COALESCE(qf.favorites, 0) AS favorites,
    COALESCE(ts.tag_count, 0) AS tag_count,
    ts.tag_list
  FROM q_activity qa
  LEFT JOIN a_activity aa ON aa.question_id = qa.question_id
  LEFT JOIN q_links ql ON ql.question_id = qa.question_id
  LEFT JOIN q_edits qe ON qe.question_id = qa.question_id
  LEFT JOIN q_favorites qf ON qf.question_id = qa.question_id
  LEFT JOIN tag_stats ts ON ts.question_id = qa.question_id
),
scored AS (
  SELECT
    hc.*,
    EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - hc.q_created)) / 3600.0 AS age_hours,
    (
      COALESCE(hc.q_upvotes, 0) * 3
      - COALESCE(hc.q_downvotes, 0) * 2
      + LEAST(COALESCE(hc.q_views, 0) / 100.0, 200)
      + COALESCE(hc.answers_positive, 0) * 2
      - COALESCE(hc.answers_negative, 0)
      + COALESCE(hc.unique_answerers, 0) * 1.5
      + COALESCE(hc.edit_events, 0) * 1
      + COALESCE(hc.links_linked, 0) * 0.5
      - COALESCE(hc.links_duplicates, 0) * 5
      + COALESCE(hc.favorites, 0) * 2
      + COALESCE(hc.q_score, 0) * 1.5
      + GREATEST(0, 5 - COALESCE(hc.tag_count, 0))
    ) / NULLIF(
      1
      + (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - hc.q_created)) / 3600.0) / 24.0,
      0
    ) AS hotness_score
  FROM hot_candidates hc
),
asker_profile AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    u.reputation,
    u.views,
    u.upvotes,
    u.downvotes,
    ur.cohort
  FROM users u
  LEFT JOIN user_recentness ur ON ur.user_id = u.id
),
top_tags AS (
  SELECT
    te.tag,
    COUNT(*) AS q_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.hotness_score) AS median_hotness
  FROM tag_expansion te
  JOIN scored s ON s.question_id = te.question_id
  GROUP BY te.tag
),
ranked AS (
  SELECT
    s.question_id,
    s.asker_id,
    s.title,
    s.tags,
    s.tag_list,
    s.q_views,
    s.q_upvotes,
    s.q_downvotes,
    s.answers_total,
    s.unique_answerers,
    s.edit_events,
    s.favorites,
    s.hotness_score,
    DENSE_RANK() OVER (ORDER BY s.hotness_score DESC) AS global_rank
  FROM scored s
)
SELECT
  r.global_rank,
  r.question_id,
  r.title,
  r.hotness_score,
  r.q_views,
  r.q_upvotes,
  r.q_downvotes,
  r.answers_total,
  r.unique_answerers,
  r.edit_events,
  r.favorites,
  ap.displayname AS asker_displayname,
  ap.reputation AS asker_reputation,
  ap.cohort AS asker_cohort,
  r.tags,
  r.tag_list,
  tt.tag AS sample_tag,
  tt.q_count AS sample_tag_qcount,
  tt.median_hotness AS sample_tag_median_hotness
FROM ranked r
LEFT JOIN asker_profile ap ON ap.user_id = r.asker_id
LEFT JOIN LATERAL (
  SELECT tt.tag, tt.q_count, tt.median_hotness
  FROM top_tags tt
  WHERE tt.tag = (
    SELECT t
    FROM UNNEST(COALESCE(r.tag_list, ARRAY[]::VARCHAR[])) AS t
    ORDER BY t
    LIMIT 1
  )
) AS tt ON TRUE
WHERE r.global_rank <= 200
ORDER BY r.global_rank, r.question_id;