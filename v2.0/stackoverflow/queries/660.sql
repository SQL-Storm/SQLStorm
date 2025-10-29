WITH
user_badge_mix AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    count(*) AS badge_count,
    sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
    sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
    sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
    max(b.date) AS last_badge_date
  FROM users u
  LEFT JOIN badges b
    ON b.userid = u.id
  WHERE u.creationdate >= (SELECT min(creationdate) FROM users)
  GROUP BY u.id, u.displayname, u.reputation, u.creationdate
  HAVING sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) > 0
     AND sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) > 0
),
question_core AS (
  SELECT
    q.id AS question_id,
    q.owneruserid,
    q.creationdate,
    q.title,
    q.score,
    q.viewcount,
    q.answercount,
    q.closeddate,
    q.acceptedanswerid,
    q.tags,
    string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') AS tag_arr,
    EXISTS (
      SELECT 1
      FROM posthistory ph
      WHERE ph.postid = q.id
        AND ph.posthistorytypeid IN (4,5,6)
      LIMIT 1
    ) AS was_edited,
    EXISTS (
      SELECT 1
      FROM posthistory phc
      WHERE phc.postid = q.id
        AND phc.posthistorytypeid = 10
      LIMIT 1
    ) AS was_closed
  FROM posts q
  WHERE q.posttypeid = 1
),
question_activity_span AS (
  SELECT
    p.id AS question_id,
    min(coalesce(p.creationdate, cast('2024-10-01 12:34:56' AS timestamp))) AS first_seen,
    max(coalesce(p.lastactivitydate, p.creationdate, cast('2024-10-01 12:34:56' AS timestamp))) AS last_seen
  FROM posts p
  WHERE p.posttypeid = 1
  GROUP BY p.id
),
vote_agg AS (
  SELECT
    v.postid,
    sum(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
    sum(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
    sum(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
    sum(CASE WHEN v.votetypeid = 8 THEN coalesce(v.bountyamount,0) ELSE 0 END) AS bounty_started,
    sum(CASE WHEN v.votetypeid = 9 THEN coalesce(v.bountyamount,0) ELSE 0 END) AS bounty_awarded,
    count(*) AS total_votes,
    max(v.creationdate) AS last_vote_at
  FROM votes v
  GROUP BY v.postid
),
question_primary_tag AS (
  SELECT
    qc.question_id,
    lower(nullif(trim(qt.tag), '')) AS primary_tag
  FROM question_core qc
  CROSS JOIN LATERAL (
    SELECT coalesce((qc.tag_arr)[1], '') AS tag
  ) AS qt
),
tag_metrics AS (
  SELECT
    t.tagname,
    t.count AS tag_total_posts,
    coalesce(t.ismoderaToronly, false) AS is_mod_only,
    coalesce(t.isrequired, false) AS is_required
  FROM tags t
),
answer_stats AS (
  SELECT
    a.parentid AS question_id,
    count(*) AS answers_total,
    count(*) FILTER (WHERE a.creationdate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '365 days') AS answers_last_year,
    sum(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS accepted_answers,
    max(a.score) AS max_answer_score,
    avg(a.score) AS avg_answer_score
  FROM posts a
  JOIN posts q ON q.id = a.parentid AND a.posttypeid = 2 AND q.posttypeid = 1
  GROUP BY a.parentid
),
comment_stats AS (
  SELECT
    c.postid AS question_id,
    count(*) AS comment_count,
    avg(c.score) AS avg_comment_score,
    max(c.creationdate) AS last_comment_at
  FROM comments c
  GROUP BY c.postid
),
closure_reasons AS (
  SELECT
    ph.postid AS question_id,
    min(ph.creationdate) AS first_close_at,
    max(ph.creationdate) AS last_close_at,
    min(nullif(ph.comment, '')) AS first_close_reason_id_text,
    array_agg(distinct ph.posthistorytypeid) AS close_event_types
  FROM posthistory ph
  WHERE ph.posthistorytypeid = 10
  GROUP BY ph.postid
),
link_stats AS (
  SELECT
    pl.postid AS question_id,
    sum(CASE WHEN pl.linktypeid = 3 THEN 1 ELSE 0 END) AS duplicate_outgoing,
    sum(CASE WHEN pl.linktypeid = 1 THEN 1 ELSE 0 END) AS linked_outgoing,
    sum(CASE WHEN pl.linktypeid = 3 THEN 0 ELSE 0 END) AS placeholder_zero,
    count(*) FILTER (WHERE pl.linktypeid = 3) AS dupe_cnt_check
  FROM postlinks pl
  GROUP BY pl.postid
),
question_ranks AS (
  SELECT
    qc.question_id,
    ntile(10) OVER (ORDER BY coalesce(qc.score,0) DESC) AS score_decile,
    ntile(10) OVER (ORDER BY coalesce(qc.viewcount,0) DESC) AS view_decile,
    rank() OVER (ORDER BY coalesce(qc.viewcount,0) DESC, qc.score DESC, qc.creationdate ASC) AS popularity_rank
  FROM question_core qc
),
owner_enriched AS (
  SELECT
    u.id AS user_id,
    coalesce(nullif(trim(u.displayname), ''), concat('user#', cast(u.id AS varchar))) AS safe_displayname,
    u.reputation,
    u.upvotes,
    u.downvotes,
    u.views AS profile_views,
    u.creationdate AS user_created,
    u.lastaccessdate AS user_last_access,
    CASE
      WHEN position('://' IN coalesce(u.websiteurl, '')) > 0
      THEN split_part(u.websiteurl, '://', 2)
      ELSE coalesce(u.websiteurl, '')
    END AS website_domainish,
    CASE WHEN u.location ILIKE '%remote%' THEN 1 ELSE 0 END AS is_remote_flag
  FROM users u
),
question_fact AS (
  SELECT
    qc.question_id,
    qc.owneruserid,
    oe.safe_displayname AS owner_displayname,
    oe.reputation AS owner_reputation,
    oe.upvotes AS owner_upvotes,
    oe.downvotes AS owner_downvotes,
    oe.profile_views AS owner_profile_views,
    qc.creationdate AS question_created,
    qc.title,
    qc.score,
    qc.viewcount,
    qc.answercount,
    qc.acceptedanswerid,
    qc.was_edited,
    qc.was_closed,
    qa.first_seen,
    qa.last_seen,
    cast(extract(epoch FROM (qa.last_seen - qa.first_seen)) AS bigint) AS activity_span_seconds,
    vs.upvotes,
    vs.downvotes,
    vs.favorites,
    vs.bounty_started,
    vs.bounty_awarded,
    vs.total_votes,
    vs.last_vote_at,
    coalesce(ans.answers_total, 0) AS answers_total,
    coalesce(ans.answers_last_year, 0) AS answers_last_year,
    coalesce(ans.accepted_answers, 0) AS accepted_answers,
    ans.max_answer_score,
    ans.avg_answer_score,
    coalesce(cs.comment_count, 0) AS comment_count,
    cs.avg_comment_score,
    cs.last_comment_at,
    cr.first_close_at,
    cr.last_close_at,
    cr.first_close_reason_id_text,
    ls.duplicate_outgoing,
    ls.linked_outgoing,
    qr.score_decile,
    qr.view_decile,
    qr.popularity_rank,
    qpt.primary_tag,
    tm.tag_total_posts,
    tm.is_mod_only,
    tm.is_required,
    qc.tags,
    qc.tag_arr
  FROM question_core qc
  LEFT JOIN owner_enriched oe ON oe.user_id = qc.owneruserid
  LEFT JOIN question_activity_span qa ON qa.question_id = qc.question_id
  LEFT JOIN vote_agg vs ON vs.postid = qc.question_id
  LEFT JOIN answer_stats ans ON ans.question_id = qc.question_id
  LEFT JOIN comment_stats cs ON cs.question_id = qc.question_id
  LEFT JOIN closure_reasons cr ON cr.question_id = qc.question_id
  LEFT JOIN link_stats ls ON ls.question_id = qc.question_id
  LEFT JOIN question_ranks qr ON qr.question_id = qc.question_id
  LEFT JOIN question_primary_tag qpt ON qpt.question_id = qc.question_id
  LEFT JOIN tag_metrics tm ON tm.tagname = qpt.primary_tag
),
user_question_rollup AS (
  SELECT
    qf.owneruserid AS user_id,
    count(*) AS questions_asked,
    count(*) FILTER (WHERE qf.acceptedanswerid IS NOT NULL) AS questions_with_accepted,
    sum(coalesce(qf.upvotes,0) - coalesce(qf.downvotes,0)) AS net_votes_sum,
    avg(qf.viewcount) AS avg_views,
    percentile_cont(0.9) WITHIN GROUP (ORDER BY coalesce(qf.viewcount,0)) AS p90_views,
    max(qf.popularity_rank) AS worst_popularity_rank,
    min(qf.popularity_rank) AS best_popularity_rank,
    sum(CASE WHEN qf.was_closed THEN 1 ELSE 0 END) AS closed_count,
    sum(CASE WHEN qf.was_edited THEN 1 ELSE 0 END) AS edited_count,
    avg(extract(epoch FROM (qf.last_seen - qf.first_seen))) AS avg_activity_span_sec
  FROM question_fact qf
  GROUP BY qf.owneruserid
),
target_users AS (
  SELECT
    ubm.user_id,
    ubm.displayname,
    ubm.reputation,
    ubm.gold_cnt,
    ubm.silver_cnt,
    ubm.bronze_cnt,
    ubm.badge_count,
    ubm.last_badge_date
  FROM user_badge_mix ubm
),
top_question_per_user AS (
  SELECT qf.*
  FROM question_fact qf
  WHERE qf.question_id IN (
    SELECT qf2.question_id
    FROM question_fact qf2
    WHERE qf2.owneruserid = qf.owneruserid
    ORDER BY
      coalesce(qf2.viewcount,0) * 0.7
      + coalesce(qf2.score,0) * 5
      + coalesce(qf2.upvotes,0) * 1.5
      - coalesce(qf2.downvotes,0) * 2
      + CASE WHEN qf2.acceptedanswerid IS NOT NULL THEN 50 ELSE 0 END
      + CASE WHEN qf2.was_closed THEN -100 ELSE 0 END
      DESC,
      qf2.question_created ASC
    LIMIT 1
  )
),
user_rankings AS (
  SELECT
    tu.user_id,
    tu.displayname,
    tu.reputation,
    tu.gold_cnt,
    tu.silver_cnt,
    tu.bronze_cnt,
    ur.questions_asked,
    ur.questions_with_accepted,
    ur.net_votes_sum,
    ur.avg_views,
    ur.p90_views,
    ur.closed_count,
    ur.edited_count,
    ur.avg_activity_span_sec,
    dense_rank() OVER (ORDER BY coalesce(ur.net_votes_sum,0) DESC, coalesce(ur.avg_views,0) DESC) AS influence_rank,
    row_number() OVER (ORDER BY coalesce(ur.questions_asked,0) DESC, coalesce(ur.p90_views,0) DESC) AS volume_rank
  FROM target_users tu
  LEFT JOIN user_question_rollup ur ON ur.user_id = tu.user_id
),
final_user AS (
  SELECT
    ur.*,
    tq.question_id AS top_question_id,
    tq.title AS top_question_title,
    tq.primary_tag AS top_question_primary_tag,
    tq.viewcount AS top_question_views,
    tq.score AS top_question_score,
    tq.upvotes AS top_question_up,
    tq.downvotes AS top_question_down,
    tq.acceptedanswerid AS top_question_has_accepted,
    tq.was_closed AS top_question_was_closed,
    tq.popularity_rank AS top_question_pop_rank
  FROM user_rankings ur
  LEFT JOIN top_question_per_user tq
    ON tq.owneruserid = ur.user_id
),
extremes AS (
  SELECT * FROM final_user WHERE influence_rank <= 50
  UNION ALL
  SELECT * FROM final_user WHERE volume_rank <= 50
),
extreme_best AS (
  SELECT
    e.*,
    row_number() OVER (
      PARTITION BY e.user_id
      ORDER BY
        least(e.influence_rank, 999999),
        least(e.volume_rank, 999999),
        e.reputation DESC
    ) AS rn
  FROM extremes e
)
SELECT
  eb.user_id,
  coalesce(oe.safe_displayname, eb.displayname) AS display_name,
  eb.reputation,
  eb.gold_cnt,
  eb.silver_cnt,
  eb.bronze_cnt,
  eb.questions_asked,
  eb.questions_with_accepted,
  eb.net_votes_sum,
  eb.avg_views,
  eb.p90_views,
  eb.closed_count,
  eb.edited_count,
  eb.avg_activity_span_sec,
  eb.influence_rank,
  eb.volume_rank,
  eb.top_question_id,
  eb.top_question_title,
  eb.top_question_primary_tag,
  eb.top_question_views,
  eb.top_question_score,
  eb.top_question_up,
  eb.top_question_down,
  eb.top_question_has_accepted,
  eb.top_question_was_closed,
  eb.top_question_pop_rank,
  CASE
    WHEN eb.gold_cnt >= 1 AND eb.silver_cnt >= 2 AND eb.bronze_cnt >= 3 THEN 'balanced'
    WHEN eb.gold_cnt >= 5 AND eb.reputation >= 10000 THEN 'elite'
    WHEN eb.closed_count > eb.questions_asked / 2 THEN 'controversial'
    ELSE 'regular'
  END AS user_archetype,
  concat_ws(' | ',
    'Q:' || coalesce(cast(eb.questions_asked AS text),'0'),
    'Acc:' || coalesce(cast(eb.questions_with_accepted AS text),'0'),
    'NetVotes:' || coalesce(cast(eb.net_votes_sum AS text),'0'),
    'TopTag:' || coalesce(eb.top_question_primary_tag,'(none)')
  ) AS compact_summary
FROM extreme_best eb
LEFT JOIN owner_enriched oe ON oe.user_id = eb.user_id
WHERE eb.rn = 1
ORDER BY eb.influence_rank, eb.volume_rank, eb.reputation DESC, eb.user_id
LIMIT 200;