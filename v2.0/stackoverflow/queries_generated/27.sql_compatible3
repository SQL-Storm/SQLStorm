WITH recent_users AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'n/a') AS websiteurl,
    date_trunc('month', u.creationdate) AS cohort_month,
    row_number() OVER (ORDER BY u.creationdate DESC, u.id DESC) AS rn_global
  FROM users u
  WHERE u.creationdate >= (SELECT max(creationdate) - interval '365 days' FROM users)
),
user_posts AS (
  SELECT
    p.owneruserid AS user_id,
    p.id AS post_id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.tags,
    COALESCE(NULLIF(p.title, ''), '[no title]') AS title,
    row_number() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate) AS rn_user_post,
    lead(p.creationdate) OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate) AS next_post_dt
  FROM posts p
  WHERE p.owneruserid IS NOT NULL
),
question_tag_unpacked AS (
  SELECT
    p.id AS post_id,
    lower(trim(tg)) AS tag
  FROM posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.tags FROM 2 FOR length(p.tags)-2), '><'))
  ) s(tg)
  WHERE p.posttypeid = 1
    AND p.tags IS NOT NULL
    AND p.tags LIKE '<%>'
),
tag_rank AS (
  SELECT
    q.tag,
    count(*) AS tag_q_count,
    dense_rank() OVER (ORDER BY count(*) DESC, tag) AS tag_pop_rank
  FROM question_tag_unpacked q
  GROUP BY q.tag
),
user_activity AS (
  SELECT
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    count(distinct up.post_id) AS total_posts,
    count(distinct CASE WHEN up.posttypeid = 1 THEN up.post_id END) AS total_questions,
    count(distinct CASE WHEN up.posttypeid = 2 THEN up.post_id END) AS total_answers,
    avg(up.score) FILTER (WHERE up.score IS NOT NULL) AS avg_post_score,
    max(up.viewcount) AS max_views,
    min(up.creationdate) AS first_post_date,
    max(up.creationdate) AS last_post_date,
    avg(extract(epoch FROM (up.next_post_dt - up.creationdate))/86400.0) FILTER (WHERE up.next_post_dt IS NOT NULL) AS avg_days_between_posts
  FROM recent_users ru
  LEFT JOIN user_posts up
    ON up.user_id = ru.user_id
  GROUP BY ru.user_id, ru.displayname, ru.reputation, ru.cohort_month
),
user_badges AS (
  SELECT
    b.userid AS user_id,
    count(*) AS badges_total,
    sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    sum(CASE WHEN b.tagbased = true THEN 1 ELSE 0 END) AS tag_badges
  FROM badges b
  GROUP BY b.userid
),
question_quality AS (
  SELECT
    q.id AS question_id,
    q.owneruserid AS user_id,
    q.creationdate AS q_created,
    q.score AS q_score,
    q.viewcount AS q_views,
    q.answercount AS q_answers,
    q.acceptedanswerid,
    COALESCE(q.favoritecount, 0) AS favorites,
    COALESCE(q.commentcount, 0) AS comments,
    sum(CASE WHEN v.votetypeid = 2 THEN 1 WHEN v.votetypeid = 3 THEN -1 ELSE 0 END) AS net_votes,
    max(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS has_favorite_vote
  FROM posts q
  LEFT JOIN votes v ON v.postid = q.id
  WHERE q.posttypeid = 1
  GROUP BY q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.acceptedanswerid, q.favoritecount, q.commentcount
),
answer_quality AS (
  SELECT
    a.id AS answer_id,
    a.parentid AS question_id,
    a.owneruserid AS user_id,
    a.creationdate AS a_created,
    a.score AS a_score,
    sum(CASE WHEN v.votetypeid = 2 THEN 1 WHEN v.votetypeid = 3 THEN -1 ELSE 0 END) AS net_votes
  FROM posts a
  LEFT JOIN votes v ON v.postid = a.id
  WHERE a.posttypeid = 2
  GROUP BY a.id, a.parentid, a.owneruserid, a.creationdate, a.score
),
dup_links AS (
  SELECT pl.postid AS dup_post_id, pl.relatedpostid AS orig_post_id
  FROM postlinks pl
  WHERE pl.linktypeid = 3
),
close_events AS (
  SELECT
    ph.postid,
    min(ph.creationdate) AS first_close_date,
    count(*) AS close_events
  FROM posthistory ph
  WHERE ph.posthistorytypeid = 10
  GROUP BY ph.postid
),
post_status AS (
  SELECT
    q.question_id,
    COALESCE(cr.first_close_date, q.q_created) AS first_gate_date,
    CASE WHEN cr.first_close_date IS NOT NULL THEN 1 ELSE 0 END AS was_closed,
    CASE WHEN d.orig_post_id IS NOT NULL THEN 1 ELSE 0 END AS marked_duplicate,
    greatest(q.q_score, COALESCE(q.net_votes, 0)) AS effective_score
  FROM question_quality q
  LEFT JOIN close_events cr ON cr.postid = q.question_id
  LEFT JOIN dup_links d ON d.dup_post_id = q.question_id
),
question_enriched AS (
  SELECT
    q.*,
    ps.was_closed,
    ps.marked_duplicate,
    ps.effective_score,
    CASE
      WHEN q.acceptedanswerid IS NOT NULL THEN 1
      WHEN EXISTS (
        SELECT 1
        FROM answer_quality a
        WHERE a.question_id = q.question_id
          AND a.a_score > 0
      ) THEN 1
      ELSE 0
    END AS has_positive_or_accepted_answer
  FROM question_quality q
  LEFT JOIN post_status ps ON ps.question_id = q.question_id
),
user_tag_focus AS (
  SELECT
    p.owneruserid AS user_id,
    qtu.tag,
    count(*) AS tag_posts,
    sum(CASE WHEN p.posttypeid = 1 THEN 1 ELSE 0 END) AS tag_questions,
    sum(CASE WHEN p.posttypeid = 2 THEN 1 ELSE 0 END) AS tag_answers
  FROM posts p
  JOIN question_tag_unpacked qtu
    ON qtu.post_id = CASE WHEN p.posttypeid = 1 THEN p.id ELSE p.parentid END
  WHERE p.posttypeid IN (1,2)
  GROUP BY p.owneruserid, qtu.tag
),
best_user_tag AS (
  SELECT
    utf.user_id,
    utf.tag,
    utf.tag_posts,
    rank() OVER (PARTITION BY utf.user_id ORDER BY utf.tag_posts DESC, utf.tag ASC) AS rnk
  FROM user_tag_focus utf
),
activity_streaks AS (
  SELECT
    up.user_id,
    date_trunc('day', up.creationdate) AS day,
    count(*) AS posts_that_day
  FROM user_posts up
  GROUP BY up.user_id, date_trunc('day', up.creationdate)
),
streak_lagged AS (
  SELECT
    a.user_id,
    day,
    lag(day) OVER (PARTITION BY a.user_id ORDER BY day) AS prev_day
  FROM activity_streaks a
),
streak_calc AS (
  SELECT
    s.user_id,
    s.day,
    CASE WHEN s.prev_day = s.day - INTERVAL '1 day' THEN 0 ELSE 1 END AS is_new_streak
  FROM streak_lagged s
),
streak_grouped AS (
  SELECT
    sc.user_id,
    sc.day,
    sum(is_new_streak) OVER (PARTITION BY sc.user_id ORDER BY sc.day ROWS UNBOUNDED PRECEDING) AS streak_group
  FROM streak_calc sc
),
streak_len AS (
  SELECT
    user_id,
    max(count(*)) OVER (PARTITION BY user_id) AS longest_posting_streak
  FROM streak_grouped
  GROUP BY user_id, streak_group
),
user_comment_agg AS (
  SELECT
    c.userid AS user_id,
    count(*) AS comments_total,
    avg(c.score) AS avg_comment_score,
    sum(CASE WHEN c.text ilike '%thanks%' OR c.text ilike '%thank you%' THEN 1 ELSE 0 END) AS polite_comments
  FROM comments c
  WHERE c.userid IS NOT NULL
  GROUP BY c.userid
),
hot_network_events AS (
  SELECT
    ph.postid AS question_id,
    count(*) AS hot_events
  FROM posthistory ph
  WHERE ph.posthistorytypeid IN (52,53)
  GROUP BY ph.postid
),
-- compute global median of q_views without ordered-set aggregate with OVER by using a percentile subquery
question_rank AS (
  SELECT
    qe.user_id,
    qe.question_id,
    qe.q_score,
    qe.q_views,
    qe.net_votes,
    qe.has_positive_or_accepted_answer,
    qe.was_closed,
    qe.marked_duplicate,
    hn.hot_events,
    -- global median computed from derived table
    mq.global_median_views,
    row_number() OVER (PARTITION BY qe.user_id ORDER BY coalesce(qe.q_views,0) DESC, qe.q_score DESC, qe.question_id) AS rn_views_desc
  FROM question_enriched qe
  LEFT JOIN hot_network_events hn ON hn.question_id = qe.question_id
  CROSS JOIN (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY q_views) AS global_median_views
    FROM question_enriched
  ) mq
),
user_recent_bad_events AS (
  SELECT
    q.user_id,
    sum(CASE WHEN q.was_closed = 1 THEN 1 ELSE 0 END) AS recent_closed_questions,
    sum(CASE WHEN q.marked_duplicate = 1 THEN 1 ELSE 0 END) AS recent_duplicates
  FROM question_rank q
  WHERE q.rn_views_desc <= 20
  GROUP BY q.user_id
),
cohort_stats AS (
  SELECT
    ua.cohort_month,
    count(*) AS users_in_cohort,
    avg(ua.total_posts) AS avg_posts_per_user,
    avg(ua.avg_post_score) AS avg_avg_score,
    -- compute p90 using a percentile subquery per cohort
    pct.p90_posts
  FROM user_activity ua
  LEFT JOIN LATERAL (
    SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY total_posts) AS p90_posts
    FROM user_activity u2
    WHERE u2.cohort_month = ua.cohort_month
  ) pct ON true
  GROUP BY ua.cohort_month, pct.p90_posts
),
user_quality_score AS (
  SELECT
    ua.user_id,
    ua.displayname,
    ua.reputation,
    ua.cohort_month,
    ua.total_posts,
    ua.total_questions,
    ua.total_answers,
    ua.avg_post_score,
    ua.max_views,
    ua.first_post_date,
    ua.last_post_date,
    ua.avg_days_between_posts,
    COALESCE(ub.badges_total, 0) AS badges_total,
    COALESCE(ub.gold_badges, 0) AS gold_badges,
    COALESCE(ub.silver_badges, 0) AS silver_badges,
    COALESCE(ub.bronze_badges, 0) AS bronze_badges,
    COALESCE(ub.tag_badges, 0) AS tag_badges,
    COALESCE(uc.comments_total, 0) AS comments_total,
    COALESCE(uc.avg_comment_score, 0) AS avg_comment_score,
    COALESCE(uc.polite_comments, 0) AS polite_comments,
    COALESCE(sl.longest_posting_streak, 0) AS longest_posting_streak,
    COALESCE(urb.recent_closed_questions, 0) AS recent_closed_questions,
    COALESCE(urb.recent_duplicates, 0) AS recent_duplicates,
    0.4 * COALESCE(ua.avg_post_score, 0)
      + 0.2 * greatest(COALESCE(ua.max_views, 0), 0) / nullif((SELECT avg(max_views) FROM user_activity), 0)
      + 0.15 * COALESCE(ub.badges_total, 0)
      + 0.1 * COALESCE(sl.longest_posting_streak, 0)
      + 0.1 * COALESCE(uc.avg_comment_score, 0)
      - 0.25 * COALESCE(urb.recent_closed_questions, 0)
      - 0.15 * COALESCE(urb.recent_duplicates, 0) AS quality_score
  FROM user_activity ua
  LEFT JOIN user_badges ub ON ub.user_id = ua.user_id
  LEFT JOIN user_comment_agg uc ON uc.user_id = ua.user_id
  LEFT JOIN streak_len sl ON sl.user_id = ua.user_id
  LEFT JOIN user_recent_bad_events urb ON urb.user_id = ua.user_id
),
best_tag_labeled AS (
  SELECT
    but.user_id,
    but.tag,
    but.tag_posts,
    tr.tag_pop_rank,
    row_number() OVER (PARTITION BY but.user_id ORDER BY but.rnk, tr.tag_pop_rank, but.tag) AS rn
  FROM best_user_tag but
  LEFT JOIN tag_rank tr ON tr.tag = but.tag
  WHERE but.rnk <= 3
),
final_scored AS (
  SELECT
    uqs.*,
    bt.tag AS top_tag,
    bt.tag_pop_rank,
    cs.users_in_cohort,
    cs.avg_posts_per_user,
    CASE
      WHEN uqs.total_posts >= cs.p90_posts THEN 'Top 10%'
      WHEN uqs.total_posts >= cs.avg_posts_per_user THEN 'Above Avg'
      ELSE 'Below Avg'
    END AS cohort_activity_band
  FROM user_quality_score uqs
  LEFT JOIN best_tag_labeled bt ON bt.user_id = uqs.user_id AND bt.rn = 1
  LEFT JOIN cohort_stats cs ON cs.cohort_month = uqs.cohort_month
),
top_questions_per_user AS (
  SELECT
    qr.user_id,
    qr.question_id,
    qr.q_views,
    qr.q_score,
    qr.net_votes,
    qr.has_positive_or_accepted_answer,
    qr.was_closed,
    qr.marked_duplicate,
    qr.hot_events,
    dense_rank() OVER (PARTITION BY qr.user_id ORDER BY coalesce(qr.q_views,0) DESC, qr.q_score DESC) AS dr
  FROM question_rank qr
)
SELECT
  fs.user_id,
  fs.displayname,
  fs.reputation,
  fs.cohort_month,
  fs.total_posts,
  fs.total_questions,
  fs.total_answers,
  round(fs.quality_score, 3) AS quality_score,
  fs.top_tag,
  fs.tag_pop_rank,
  fs.cohort_activity_band,
  fs.users_in_cohort,
  fs.avg_posts_per_user,
  coalesce(tq.question_id, -1) AS top_question_id,
  tq.q_views AS top_question_views,
  tq.q_score AS top_question_score,
  tq.net_votes AS top_question_net_votes,
  tq.has_positive_or_accepted_answer AS top_question_has_good_answer,
  tq.hot_events AS top_question_hot_events,
  CASE
    WHEN fs.tag_pop_rank IS NULL THEN 'generalist'
    WHEN fs.tag_pop_rank <= 50 THEN 'expert-in-popular-tag'
    WHEN fs.tag_pop_rank <= 200 THEN 'niche-expert'
    ELSE 'long-tail'
  END AS specialization_bucket
FROM final_scored fs
LEFT JOIN top_questions_per_user tq
  ON tq.user_id = fs.user_id
 AND tq.dr = 1
WHERE coalesce(fs.reputation, 0) >= 1
  AND (fs.total_posts > 0 OR fs.badges_total > 0)
ORDER BY fs.quality_score DESC NULLS LAST, fs.reputation DESC, fs.user_id
LIMIT 250;