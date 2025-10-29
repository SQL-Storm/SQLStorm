WITH recent_users AS (
    SELECT u.id AS user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'unknown') AS website_norm,
           date_trunc('month', u.creationdate) AS cohort_month
    FROM users u
    WHERE u.creationdate >= (
        SELECT date_trunc('month', MAX(p.creationdate)) - INTERVAL '24 months' FROM posts p
    )
),
user_activity AS (
    SELECT
        p.owneruserid AS user_id,
        count(*) FILTER (WHERE p.posttypeid = 1) AS q_count,
        count(*) FILTER (WHERE p.posttypeid = 2) AS a_count,
        sum(greatest(p.score, 0)) AS nonneg_post_score,
        sum(p.viewcount) AS total_views,
        count(*) FILTER (WHERE p.closeddate IS NOT NULL) AS closed_posts,
        max(p.lastactivitydate) AS last_activity
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
comment_stats AS (
    SELECT c.userid AS user_id,
           count(*) AS comment_count,
           sum(c.score) AS comment_score,
           max(c.creationdate) AS last_comment_at
    FROM comments c
    WHERE c.userid IS NOT NULL
    GROUP BY c.userid
),
badge_rollup AS (
    SELECT b.userid AS user_id,
           count(*) AS badge_count,
           count(*) FILTER (WHERE b.class = 1) AS gold_count,
           count(*) FILTER (WHERE b.class = 2) AS silver_count,
           count(*) FILTER (WHERE b.class = 3) AS bronze_count,
           min(b.date) AS first_badge_at,
           max(b.date) AS last_badge_at
    FROM badges b
    GROUP BY b.userid
),
vote_rollup AS (
    SELECT v.userid AS user_id,
           count(*) FILTER (WHERE v.votetypeid = 2) AS upvotes_cast,
           count(*) FILTER (WHERE v.votetypeid = 3) AS downvotes_cast,
           count(*) FILTER (WHERE v.votetypeid IN (8,9)) AS bounties_touched,
           sum(coalesce(v.bountyamount,0)) FILTER (WHERE v.votetypeid IN (8,9)) AS bounty_amount_total,
           max(v.creationdate) AS last_vote_at
    FROM votes v
    WHERE v.userid IS NOT NULL
    GROUP BY v.userid
),
question_detail AS (
    SELECT
        q.id AS question_id,
        q.owneruserid AS asker_id,
        q.creationdate AS asked_at,
        q.score AS q_score,
        q.viewcount AS q_views,
        q.answercount,
        q.acceptedanswerid,
        q.tags,
        q.title,
        date_trunc('month', q.creationdate) AS q_month,
        array_length(string_to_array(coalesce(substring(q.tags, 2, length(q.tags)-2), ''), '><'), 1) AS tag_count,
        q.creationdate AS creationdate,
        q.id AS id
    FROM posts q
    WHERE q.posttypeid = 1
),
answer_detail AS (
    SELECT
        a.id AS answer_id,
        a.parentid AS question_id,
        a.owneruserid AS answerer_id,
        a.creationdate AS answered_at,
        a.score AS a_score
    FROM posts a
    WHERE a.posttypeid = 2
),
accepted_answers AS (
    SELECT ad.answerer_id,
           count(*) AS accepted_count,
           avg(CAST(ad.a_score AS numeric)) AS avg_accepted_answer_score
    FROM answer_detail ad
    JOIN question_detail qd
      ON qd.acceptedanswerid = ad.answer_id
    GROUP BY ad.answerer_id
),
dup_links AS (
    SELECT pl.postid AS dup_post_id,
           pl.relatedpostid AS original_post_id,
           pl.creationdate AS link_created_at
    FROM postlinks pl
    WHERE pl.linktypeid = 3
),
closure_reasons AS (
    SELECT ph.postid,
           max(ph.creationdate) FILTER (WHERE ph.posthistorytypeid = 10) AS closed_at,
           max(ph.creationdate) FILTER (WHERE ph.posthistorytypeid = 11) AS reopened_at,
           max(CAST(ph.comment AS integer)) FILTER (WHERE ph.posthistorytypeid = 10 AND ph.comment ~ '^[0-9]+$') AS last_close_reason_id
    FROM posthistory ph
    GROUP BY ph.postid
),
closed_question_detail AS (
    SELECT qd.question_id,
           cr.closed_at,
           cr.last_close_reason_id,
           CASE
             WHEN cr.last_close_reason_id IN (1,101) THEN 'duplicate'
             WHEN cr.last_close_reason_id IN (102) THEN 'off-topic'
             WHEN cr.last_close_reason_id IN (103) THEN 'needs-details'
             WHEN cr.last_close_reason_id IN (104) THEN 'needs-focus'
             WHEN cr.last_close_reason_id IN (105) THEN 'opinion-based'
             ELSE 'other-or-unknown'
           END AS close_bucket
    FROM question_detail qd
    JOIN closure_reasons cr ON cr.postid = qd.question_id
    WHERE cr.closed_at IS NOT NULL
),
tag_exploded AS (
    SELECT
        qd.question_id,
        unnest(string_to_array(coalesce(substring(qd.tags, 2, length(qd.tags)-2), ''), '><')) AS tag
    FROM question_detail qd
),
tag_popularity AS (
    SELECT te.tag,
           count(*) AS q_count,
           avg(CAST(qd.q_score AS numeric)) AS avg_q_score,
           percentile_cont(0.9) WITHIN GROUP (ORDER BY qd.q_views) AS p90_views
    FROM tag_exploded te
    JOIN question_detail qd ON qd.question_id = te.question_id
    GROUP BY te.tag
),
user_tag_focus AS (
    SELECT qd.asker_id AS user_id,
           te.tag,
           count(*) AS questions_with_tag,
           row_number() OVER (PARTITION BY qd.asker_id ORDER BY count(*) DESC, min(qd.creationdate)) AS rn,
           min(qd.creationdate) AS min_creationdate
    FROM question_detail qd
    JOIN tag_exploded te ON te.question_id = qd.question_id
    GROUP BY qd.asker_id, te.tag
),
user_latest_activity AS (
    SELECT ua.user_id,
           greatest(coalesce(ua.last_activity, TIMESTAMP 'epoch'),
                    coalesce(cs.last_comment_at, TIMESTAMP 'epoch'),
                    coalesce(vr.last_vote_at, TIMESTAMP 'epoch'),
                    coalesce(br.last_badge_at, TIMESTAMP 'epoch')) AS last_seen_at
    FROM user_activity ua
    LEFT JOIN comment_stats cs ON cs.user_id = ua.user_id
    LEFT JOIN vote_rollup vr ON vr.user_id = ua.user_id
    LEFT JOIN badge_rollup br ON br.user_id = ua.user_id
),
user_quality AS (
    SELECT
        coalesce(u.id, ra.user_id, cs.user_id, vr.user_id, br.user_id) AS user_id,
        u.displayname,
        u.reputation,
        coalesce(ra.q_count,0) AS q_count,
        coalesce(ra.a_count,0) AS a_count,
        coalesce(ra.nonneg_post_score,0) AS post_score_nonneg,
        coalesce(ra.total_views,0) AS total_views,
        coalesce(cs.comment_count,0) AS comment_count,
        coalesce(cs.comment_score,0) AS comment_score,
        coalesce(vr.upvotes_cast,0) AS upvotes_cast,
        coalesce(vr.downvotes_cast,0) AS downvotes_cast,
        coalesce(vr.bounty_amount_total,0) AS bounty_amount_total,
        coalesce(br.badge_count,0) AS badge_count,
        coalesce(br.gold_count,0) AS gold_count,
        coalesce(br.silver_count,0) AS silver_count,
        coalesce(br.bronze_count,0) AS bronze_count,
        ul.last_seen_at,
        ru.cohort_month,
        ru.website_norm,
        ru.location
    FROM users u
    FULL OUTER JOIN user_activity ra ON ra.user_id = u.id
    FULL OUTER JOIN comment_stats cs ON cs.user_id = coalesce(u.id, ra.user_id)
    FULL OUTER JOIN vote_rollup vr ON vr.user_id = coalesce(u.id, ra.user_id, cs.user_id)
    FULL OUTER JOIN badge_rollup br ON br.user_id = coalesce(u.id, ra.user_id, cs.user_id, vr.user_id)
    LEFT JOIN recent_users ru ON ru.user_id = coalesce(u.id, ra.user_id, cs.user_id, vr.user_id, br.user_id)
    LEFT JOIN user_latest_activity ul ON ul.user_id = coalesce(u.id, ra.user_id, cs.user_id, vr.user_id, br.user_id)
),
answer_speed AS (
    SELECT
        qd.question_id,
        min(extract(epoch FROM (ad.answered_at - qd.asked_at))) AS first_answer_seconds,
        avg(extract(epoch FROM (ad.answered_at - qd.asked_at))) AS avg_answer_seconds
    FROM question_detail qd
    LEFT JOIN answer_detail ad ON ad.question_id = qd.question_id
    GROUP BY qd.question_id
),
answerers_per_q AS (
    SELECT qd.question_id,
           count(DISTINCT ad.answerer_id) AS distinct_answerers
    FROM question_detail qd
    LEFT JOIN answer_detail ad ON ad.question_id = qd.question_id
    GROUP BY qd.question_id
),
q_engagement AS (
    SELECT
        qd.question_id,
        coalesce(asd.first_answer_seconds, NULL) AS first_answer_seconds,
        coalesce(asd.avg_answer_seconds, NULL) AS avg_answer_seconds,
        apq.distinct_answerers,
        greatest(1, qd.answercount) AS answercount_safe
    FROM question_detail qd
    LEFT JOIN answer_speed asd ON asd.question_id = qd.question_id
    LEFT JOIN answerers_per_q apq ON apq.question_id = qd.question_id
),
dup_resolution AS (
    SELECT
        qd.question_id,
        CASE WHEN d.dup_post_id IS NOT NULL THEN 1 ELSE 0 END AS is_duplicate,
        d.original_post_id,
        d.link_created_at
    FROM question_detail qd
    LEFT JOIN dup_links d ON d.dup_post_id = qd.question_id
),
user_accept_stats AS (
    SELECT
        coalesce(uq.user_id, aa.answerer_id) AS user_id,
        coalesce(aa.accepted_count, 0) AS accepted_answers,
        coalesce(aa.avg_accepted_answer_score, 0) AS avg_accepted_answer_score
    FROM user_quality uq
    LEFT JOIN accepted_answers aa ON aa.answerer_id = uq.user_id
),
posttype_names AS (
    SELECT id, lower(name) AS name FROM posttypes
),
vote_type_names AS (
    SELECT id, lower(name) AS name FROM votetypes
),
close_reason_names AS (
    SELECT id, lower(name) AS name FROM closereasontypes
),
q_activity_window AS (
    SELECT
        qd.question_id,
        qd.asker_id,
        qd.q_month,
        sum(qd.q_score) OVER (PARTITION BY qd.asker_id, qd.q_month) AS monthly_q_score_by_user,
        sum(qd.q_views) OVER (PARTITION BY qd.q_month) AS monthly_views_all,
        row_number() OVER (PARTITION BY qd.asker_id ORDER BY qd.creationdate DESC, qd.id DESC) AS rn_latest_q,
        qd.creationdate,
        qd.id,
        qd.q_views AS viewcount,
        qd.q_score
    FROM question_detail qd
),
heavy_users AS (
    SELECT uq.user_id
    FROM user_quality uq
    WHERE coalesce(uq.q_count,0) + coalesce(uq.a_count,0) >= 50
),
risk_flags AS (
    SELECT
        uq.user_id,
        (CASE WHEN uq.downvotes_cast > uq.upvotes_cast AND uq.reputation < 100 THEN 1 ELSE 0 END) AS likely_troll,
        (CASE WHEN uq.closed_posts >= 5 AND uq.q_count > 0 THEN 1 ELSE 0 END) AS low_quality_asker,
        (CASE WHEN uq.gold_count >= 1 OR uq.reputation >= 20000 THEN 1 ELSE 0 END) AS elite_user
    FROM (
        SELECT
            uq.*,
            coalesce((SELECT count(*) FROM posts p WHERE p.owneruserid = uq.user_id AND p.posttypeid = 1 AND p.closeddate IS NOT NULL), 0) AS closed_posts
        FROM user_quality uq
    ) uq
),
final AS (
    SELECT
        uq.user_id,
        uq.displayname,
        uq.reputation,
        uq.q_count,
        uq.a_count,
        uq.post_score_nonneg,
        uq.total_views,
        uq.comment_count,
        uq.comment_score,
        uq.upvotes_cast,
        uq.downvotes_cast,
        uq.bounty_amount_total,
        uq.badge_count,
        uq.gold_count,
        uq.silver_count,
        uq.bronze_count,
        uq.last_seen_at,
        uq.cohort_month,
        uq.website_norm,
        uq.location,
        uaf.accepted_answers,
        uaf.avg_accepted_answer_score,
        coalesce(ut.tag, '(none)') AS top_tag,
        tpop.q_count AS top_tag_q_count,
        tpop.avg_q_score AS top_tag_avg_q_score,
        tpop.p90_views AS top_tag_p90_views,
        rq.monthly_q_score_by_user,
        rq.monthly_views_all,
        rq.rn_latest_q,
        rf.likely_troll,
        rf.low_quality_asker,
        rf.elite_user
    FROM user_quality uq
    LEFT JOIN user_accept_stats uaf ON uaf.user_id = uq.user_id
    LEFT JOIN user_tag_focus ut ON ut.user_id = uq.user_id AND ut.rn = 1
    LEFT JOIN tag_popularity tpop ON tpop.tag = ut.tag
    LEFT JOIN q_activity_window rq ON rq.asker_id = uq.user_id AND rq.rn_latest_q = 1
    LEFT JOIN risk_flags rf ON rf.user_id = uq.user_id
    WHERE (uq.reputation > 100 OR rf.elite_user = 1 OR uq.badge_count >= 10)
),
heavy_vs_others AS (
    SELECT f.*,
           CASE WHEN hu.user_id IS NOT NULL THEN 'heavy' ELSE 'other' END AS user_segment
    FROM final f
    LEFT JOIN heavy_users hu ON hu.user_id = f.user_id
),
comment_trend AS (
    SELECT
        u.id AS user_id,
        (SELECT avg(c2.score) FROM comments c2 WHERE c2.userid = u.id AND c2.creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days') AS avg_comment_score_90d,
        (SELECT count(*) FROM comments c3 WHERE c3.userid = u.id AND c3.creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days') AS comments_last_7d
    FROM users u
),
scored_final AS (
    SELECT
    hvo.user_segment,
    hvo.user_id,
    coalesce(hvo.displayname, concat('user#', CAST(hvo.user_id AS text))) AS displayname_fallback,
    hvo.reputation,
    hvo.q_count,
    hvo.a_count,
    hvo.accepted_answers,
    round(coalesce(hvo.avg_accepted_answer_score, 0), 2) AS avg_accepted_answer_score,
    hvo.badge_count,
    hvo.gold_count,
    hvo.silver_count,
    hvo.bronze_count,
    hvo.post_score_nonneg,
    hvo.total_views,
    hvo.comment_count,
    hvo.comment_score,
    hvo.upvotes_cast,
    hvo.downvotes_cast,
    hvo.bounty_amount_total,
    hvo.cohort_month,
    hvo.website_norm,
    nullif(trim(hvo.location), '') AS location,
    hvo.top_tag,
    hvo.top_tag_q_count,
    hvo.top_tag_avg_q_score,
    hvo.top_tag_p90_views,
    hvo.monthly_q_score_by_user,
    hvo.monthly_views_all,
    hvo.rn_latest_q,
    hvo.likely_troll,
    hvo.low_quality_asker,
    hvo.elite_user,
    ct.avg_comment_score_90d,
    ct.comments_last_7d,
    round( greatest(0,
        coalesce(hvo.reputation,0) / 50.0
        + coalesce(hvo.a_count,0) * 0.5
        + coalesce(hvo.q_count,0) * 0.2
        + coalesce(hvo.accepted_answers,0) * 1.5
        + coalesce(hvo.gold_count,0) * 5
        + coalesce(hvo.silver_count,0) * 2
        + coalesce(hvo.bronze_count,0) * 1
        + coalesce(hvo.post_score_nonneg,0) * 0.1
        + coalesce(hvo.comment_score,0) * 0.05
        - coalesce(hvo.downvotes_cast,0) * 0.2
        + CASE WHEN hvo.elite_user = 1 THEN 10 ELSE 0 END
        - CASE WHEN hvo.likely_troll = 1 THEN 15 ELSE 0 END
        ), 2) AS composite_quality_score,
    coalesce(nullif(hvo.website_norm, 'unknown'), 'n/a') || CASE WHEN hvo.website_norm IS NULL THEN '' ELSE ' (site)' END AS website_display,
    rank() OVER (PARTITION BY hvo.user_segment ORDER BY
        coalesce(hvo.reputation,0) DESC,
        coalesce(hvo.badge_count,0) DESC,
        coalesce(hvo.a_count,0) DESC,
        coalesce(hvo.q_count,0) DESC
    ) AS segment_rank
    FROM heavy_vs_others hvo
    LEFT JOIN comment_trend ct ON ct.user_id = hvo.user_id
)
SELECT
    sf.user_segment,
    sf.user_id,
    sf.displayname_fallback,
    sf.reputation,
    sf.q_count,
    sf.a_count,
    sf.accepted_answers,
    sf.avg_accepted_answer_score,
    sf.badge_count,
    sf.gold_count,
    sf.silver_count,
    sf.bronze_count,
    sf.post_score_nonneg,
    sf.total_views,
    sf.comment_count,
    sf.comment_score,
    sf.upvotes_cast,
    sf.downvotes_cast,
    sf.bounty_amount_total,
    sf.cohort_month,
    sf.website_norm,
    sf.location,
    sf.top_tag,
    sf.top_tag_q_count,
    sf.top_tag_avg_q_score,
    sf.top_tag_p90_views,
    sf.monthly_q_score_by_user,
    sf.monthly_views_all,
    sf.rn_latest_q,
    sf.likely_troll,
    sf.low_quality_asker,
    sf.elite_user,
    sf.avg_comment_score_90d,
    sf.comments_last_7d,
    sf.composite_quality_score,
    sf.website_display,
    sf.segment_rank
FROM scored_final sf
WHERE sf.segment_rank <= 100
   OR sf.composite_quality_score >= (
       SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY
            coalesce(f.reputation,0)/50.0
            + coalesce(f.a_count,0) * 0.5
            + coalesce(f.q_count,0) * 0.2
            + coalesce(f.accepted_answers,0) * 1.5
            + coalesce(f.gold_count,0) * 5
            + coalesce(f.silver_count,0) * 2
            + coalesce(f.bronze_count,0) * 1
            + coalesce(f.post_score_nonneg,0) * 0.1
            + coalesce(f.comment_score,0) * 0.05
            - coalesce(f.downvotes_cast,0) * 0.2
            + CASE WHEN f.elite_user = 1 THEN 10 ELSE 0 END
            - CASE WHEN f.likely_troll = 1 THEN 15 ELSE 0 END
       ) FROM final f
)
ORDER BY user_segment, segment_rank, user_id;