WITH recent_users AS (
  SELECT u.id AS user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         date_trunc('month', u.creationdate) AS signup_month,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '//', 2)), ''), 'none') AS website_domain
  FROM users u
  WHERE u.creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - interval '5 years'
),
q AS (
  SELECT p.id AS post_id,
         p.owneruserid AS user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.commentcount,
         p.favoritecount,
         p.tags,
         p.title
  FROM posts p
  WHERE p.posttypeid = 1
),
a AS (
  SELECT p.id AS post_id,
         p.parentid AS question_id,
         p.owneruserid AS user_id,
         p.creationdate,
         p.score
  FROM posts p
  WHERE p.posttypeid = 2
),
votes_cte AS (
  SELECT v.postid,
         sum(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
         sum(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
         sum(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
         sum(CASE WHEN v.votetypeid = 8 THEN coalesce(v.bountyamount,0) ELSE 0 END) AS bounty_started,
         sum(CASE WHEN v.votetypeid = 9 THEN coalesce(v.bountyamount,0) ELSE 0 END) AS bounty_awarded,
         count(*) AS total_votes,
         min(v.creationdate) AS first_vote_at,
         max(v.creationdate) AS last_vote_at
  FROM votes v
  GROUP BY v.postid
),
comments_agg AS (
  SELECT c.postid,
         count(*) AS comments_count,
         sum(CASE WHEN c.score > 0 THEN 1 ELSE 0 END) AS pos_comments,
         sum(CASE WHEN c.score < 0 THEN 1 ELSE 0 END) AS neg_comments,
         max(c.score) AS max_comment_score,
         string_agg(left(c.text, 80), ' | ' ORDER BY c.score DESC, c.creationdate) AS sample_comments
  FROM comments c
  GROUP BY c.postid
),
tag_expanded AS (
  SELECT q.post_id,
         unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) AS tag
  FROM q
  WHERE q.tags IS NOT NULL
),
top_tag_users AS (
  SELECT u.id AS user_id,
         t.tag,
         count(*) AS posts_with_tag,
         rank() OVER (PARTITION BY t.tag ORDER BY count(*) DESC, u.id) AS rnk_by_tag
  FROM tag_expanded t
  JOIN posts p ON p.id = t.post_id
  JOIN users u ON u.id = p.owneruserid
  GROUP BY u.id, t.tag
),
postlinks_agg AS (
  SELECT pl.postid,
         sum(CASE WHEN pl.linktypeid = 1 THEN 1 ELSE 0 END) AS linked_count,
         sum(CASE WHEN pl.linktypeid = 3 THEN 1 ELSE 0 END) AS duplicate_count,
         max(CASE WHEN pl.linktypeid = 3 THEN pl.relatedpostid END) AS example_duplicate_of
  FROM postlinks pl
  GROUP BY pl.postid
),
edits AS (
  SELECT ph.postid,
         count(*) FILTER (WHERE ph.posthistorytypeid IN (4,5,6,7,8,9,24)) AS edit_events,
         min(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (4,5,6,24)) AS first_edit_at,
         max(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (4,5,6,24)) AS last_edit_at,
         count(*) FILTER (WHERE ph.posthistorytypeid = 10) AS close_events,
         max( CASE WHEN ph.comment ~ '^[0-9]+$' THEN CAST(ph.comment AS integer) ELSE NULL END * 1 ) FILTER (WHERE ph.posthistorytypeid = 10) AS last_close_reason_code
  FROM posthistory ph
  GROUP BY ph.postid
),
answers_agg AS (
  SELECT a.question_id,
         count(*) AS answer_count,
         avg(a.score) AS avg_answer_score,
         max(a.score) AS max_answer_score,
         min(a.creationdate) AS first_answer_at,
         max(a.creationdate) AS last_answer_at
  FROM a
  GROUP BY a.question_id
),
badges_agg AS (
  SELECT b.userid,
         count(*) AS total_badges,
         sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
         max(b.date) AS last_badge_at
  FROM badges b
  GROUP BY b.userid
),
user_activity AS (
  SELECT u.id AS user_id,
         count(*) FILTER (WHERE p.posttypeid = 1) AS questions_posted,
         count(*) FILTER (WHERE p.posttypeid = 2) AS answers_posted,
         coalesce(sum(p.score) FILTER (WHERE p.posttypeid IN (1,2)),0) AS total_post_score,
         max(p.lastactivitydate) AS last_activity,
         count(DISTINCT date_trunc('day', p.creationdate)) AS active_days
  FROM users u
  LEFT JOIN posts p ON p.owneruserid = u.id
  GROUP BY u.id
),
question_metrics AS (
  SELECT q.post_id,
         q.user_id,
         q.creationdate AS question_created_at,
         q.score AS question_score,
         coalesce(q.viewcount,0) AS views,
         coalesce(v.upvotes,0) AS upvotes,
         coalesce(v.downvotes,0) AS downvotes,
         coalesce(v.favorites,0) AS favorites,
         coalesce(c.comments_count,0) AS comments_count,
         coalesce(c.pos_comments,0) AS pos_comments,
         coalesce(c.neg_comments,0) AS neg_comments,
         coalesce(pa.linked_count,0) AS linked_count,
         coalesce(pa.duplicate_count,0) AS duplicate_count,
         coalesce(pa.example_duplicate_of,0) AS example_duplicate_of,
         coalesce(e.edit_events,0) AS edit_events,
         e.first_edit_at,
         e.last_edit_at,
         coalesce(e.close_events,0) AS close_events,
         e.last_close_reason_code,
         coalesce(ans.answer_count,0) AS answers,
         ans.avg_answer_score,
         ans.max_answer_score,
         ans.first_answer_at,
         ans.last_answer_at,
         CASE WHEN q.answercount IS NULL THEN coalesce(ans.answer_count,0) ELSE q.answercount END AS answercount_reported,
         length(coalesce(q.title,'')) AS title_len,
         array_length(string_to_array(coalesce(substring(q.tags, 2, greatest(length(q.tags)-2,0)) ,''), '><'), 1) AS tag_count
  FROM q
  LEFT JOIN votes_cte v ON v.postid = q.post_id
  LEFT JOIN comments_agg c ON c.postid = q.post_id
  LEFT JOIN postlinks_agg pa ON pa.postid = q.post_id
  LEFT JOIN edits e ON e.postid = q.post_id
  LEFT JOIN answers_agg ans ON ans.question_id = q.post_id
),
ranked_questions AS (
  SELECT qm.post_id,
         qm.user_id,
         qm.question_created_at,
         qm.question_score,
         qm.views,
         qm.upvotes,
         qm.downvotes,
         qm.favorites,
         qm.comments_count,
         qm.pos_comments,
         qm.neg_comments,
         qm.linked_count,
         qm.duplicate_count,
         qm.example_duplicate_of,
         qm.edit_events,
         qm.first_edit_at,
         qm.last_edit_at,
         qm.close_events,
         qm.last_close_reason_code,
         qm.answers,
         qm.avg_answer_score,
         qm.max_answer_score,
         qm.first_answer_at,
         qm.last_answer_at,
         qm.answercount_reported,
         qm.title_len,
         qm.tag_count,
         row_number() OVER (PARTITION BY qm.user_id ORDER BY qm.views DESC, qm.question_score DESC, qm.post_id) AS rn_views,
         row_number() OVER (PARTITION BY qm.user_id ORDER BY coalesce(qm.upvotes - qm.downvotes,0) DESC, qm.post_id) AS rn_netvotes,
         ntile(10) OVER (ORDER BY coalesce(qm.views,0) DESC) AS views_decile,
         rank() OVER (ORDER BY (coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0)) DESC NULLS LAST) AS sitewide_vote_rank
  FROM question_metrics qm
),
power_users AS (
  SELECT ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.signup_month,
         coalesce(b.total_badges,0) AS total_badges,
         coalesce(b.gold_badges,0) AS gold_badges,
         coalesce(b.silver_badges,0) AS silver_badges,
         coalesce(b.bronze_badges,0) AS bronze_badges,
         ua.questions_posted,
         ua.answers_posted,
         ua.total_post_score,
         ua.last_activity,
         ua.active_days,
         ru.website_domain
  FROM recent_users ru
  LEFT JOIN badges_agg b ON b.userid = ru.user_id
  LEFT JOIN user_activity ua ON ua.user_id = ru.user_id
  WHERE coalesce(ua.questions_posted,0) + coalesce(ua.answers_posted,0) > 0
),
picked_question AS (
  SELECT rq.*
  FROM ranked_questions rq
  WHERE rq.rn_views <= 3
     OR rq.rn_netvotes = 1
),
eligible AS (
  SELECT pq.post_id,
         pq.user_id,
         pq.views_decile,
         pq.sitewide_vote_rank,
         pq.tag_count,
         pq.edit_events,
         pq.close_events,
         pq.answers,
         pq.answercount_reported,
         pq.last_answer_at,
         pq.duplicate_count,
         pq.upvotes,
         pq.downvotes,
         pq.favorites,
         pq.comments_count,
         pq.title_len
  FROM picked_question pq
  WHERE (pq.views_decile <= 3 AND pq.answers >= 1)
     OR (pq.duplicate_count = 0 AND pq.tag_count BETWEEN 2 AND 5)
)
SELECT
  pu.user_id,
  pu.displayname,
  pu.reputation,
  pu.signup_month,
  pu.total_badges,
  pu.gold_badges,
  pu.silver_badges,
  pu.bronze_badges,
  pu.questions_posted,
  pu.answers_posted,
  pu.total_post_score,
  pu.last_activity,
  pu.active_days,
  pu.website_domain,
  e.post_id,
  coalesce(pt.name, 'Unknown') AS post_type_name,
  rq.question_score,
  rq.views,
  e.views_decile,
  e.sitewide_vote_rank,
  e.tag_count,
  e.edit_events,
  e.close_events,
  e.answers,
  e.answercount_reported,
  coalesce(date_part('epoch', e.last_answer_at - rq.question_created_at)/3600.0, NULL) AS hours_to_last_answer,
  e.duplicate_count,
  coalesce(e.upvotes,0) - coalesce(e.downvotes,0) AS net_votes,
  e.favorites,
  e.comments_count,
  e.title_len,
  CASE
    WHEN e.close_events > 0 THEN 'closed'
    WHEN e.duplicate_count > 0 THEN 'duplicate'
    WHEN e.answers = 0 AND coalesce(e.upvotes,0) + coalesce(e.downvotes,0) = 0 THEN 'unanswered-unvoted'
    ELSE 'active'
  END AS question_state,
  CASE WHEN tt.rnk_by_tag = 1 THEN tt.tag ELSE NULL END AS top_tag_by_user,
  coalesce(ca.sample_comments, '') AS comment_samples,
  pl.example_duplicate_of,
  left(coalesce(q.title,''), 140) AS title_sample
FROM eligible e
JOIN ranked_questions rq ON rq.post_id = e.post_id
LEFT JOIN q ON q.post_id = e.post_id
LEFT JOIN posts p ON p.id = e.post_id
LEFT JOIN posttypes pt ON pt.id = p.posttypeid
LEFT JOIN power_users pu ON pu.user_id = rq.user_id
LEFT JOIN comments_agg ca ON ca.postid = e.post_id
LEFT JOIN postlinks_agg pl ON pl.postid = e.post_id
LEFT JOIN LATERAL (
  SELECT ttu.tag, ttu.rnk_by_tag
  FROM top_tag_users ttu
  WHERE ttu.user_id = rq.user_id
  ORDER BY ttu.rnk_by_tag
  LIMIT 1
) tt ON true
WHERE pu.user_id IS NOT NULL
  AND (
    pu.reputation >= 1000
    OR (pu.gold_badges + pu.silver_badges) >= 5
    OR (pu.questions_posted + pu.answers_posted) >= 50
  )
  AND (
    (coalesce(e.upvotes,0) - coalesce(e.downvotes,0)) IS NOT NULL
    OR e.favorites > 0
    OR e.comments_count > 0
  )
ORDER BY pu.reputation DESC, e.views_decile, e.post_id
LIMIT 500;