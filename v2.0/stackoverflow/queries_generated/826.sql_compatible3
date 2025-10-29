WITH recent_users AS (
    SELECT
        u.id AS user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'unknown') AS websiteurl,
        date_trunc('month', u.creationdate) AS cohort_month,
        row_number() OVER (ORDER BY u.creationdate DESC, u.id DESC) AS rn_global
    FROM users u
    WHERE u.creationdate >= (SELECT max(creationdate) - INTERVAL '365 days' FROM users)
),
user_activity AS (
    SELECT
        p.owneruserid AS user_id,
        count(*) FILTER (WHERE p.posttypeid = 1) AS q_count,
        count(*) FILTER (WHERE p.posttypeid = 2) AS a_count,
        sum(COALESCE(p.score,0)) AS post_score_sum,
        sum(COALESCE(p.viewcount,0)) AS post_views_sum,
        avg(NULLIF(p.answercount,0)) FILTER (WHERE p.posttypeid = 1) AS avg_answers_per_q_nonzero,
        max(p.creationdate) AS last_post_at,
        min(p.creationdate) AS first_post_at
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
      AND p.creationdate >= (SELECT min(creationdate) FROM recent_users)
    GROUP BY p.owneruserid
),
comment_activity AS (
    SELECT
        c.userid AS user_id,
        count(*) AS comment_count,
        sum(COALESCE(c.score,0)) AS comment_score_sum,
        max(c.creationdate) AS last_comment_at
    FROM comments c
    WHERE c.userid IS NOT NULL
      AND c.creationdate >= (SELECT min(creationdate) FROM recent_users)
    GROUP BY c.userid
),
badge_activity AS (
    SELECT
        b.userid AS user_id,
        count(*) AS badge_count,
        count(*) FILTER (WHERE b.class = 1) AS gold_badges,
        count(*) FILTER (WHERE b.class = 2) AS silver_badges,
        count(*) FILTER (WHERE b.class = 3) AS bronze_badges,
        max(b.date) AS last_badge_at
    FROM badges b
    WHERE b.date >= (SELECT min(creationdate) FROM recent_users)
    GROUP BY b.userid
),
vote_activity AS (
    SELECT
        v.userid AS user_id,
        count(*) FILTER (WHERE v.votetypeid = 2) AS upvotes_cast,
        count(*) FILTER (WHERE v.votetypeid = 3) AS downvotes_cast,
        count(*) FILTER (WHERE v.votetypeid = 10) AS deletions_cast,
        max(v.creationdate) AS last_vote_at
    FROM votes v
    WHERE v.userid IS NOT NULL
      AND v.creationdate >= (SELECT min(creationdate) FROM recent_users)
    GROUP BY v.userid
),
qa_quality AS (
    SELECT
        p.owneruserid AS user_id,
        count(*) FILTER (WHERE p.posttypeid = 1 AND p.acceptedanswerid IS NOT NULL) AS questions_with_accepted,
        count(*) FILTER (WHERE p.posttypeid = 2 AND EXISTS (
            SELECT 1
            FROM posts q
            WHERE q.id = p.parentid
              AND q.acceptedanswerid = p.id
        )) AS answers_accepted,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(p.score,0)) AS median_post_score
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
question_tag_metrics AS (
    SELECT
        p.owneruserid AS user_id,
        count(*) AS tagged_qs,
        count(*) FILTER (
            WHERE p.tags IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) t(tag)
                  WHERE lower(t.tag) IN ('sql','postgresql','mysql','tsql','oracle','sqlite')
              )
        ) AS tagged_sql_family_qs
    FROM posts p
    WHERE p.posttypeid = 1
      AND p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
post_closure_events AS (
    SELECT
        ph.postid,
        min(ph.creationdate) AS first_close_at,
        max(ph.creationdate) AS last_close_at,
        count(*) AS close_events,
        count(*) FILTER (WHERE ph.comment IN ('101','102','103','104','105','1','2','3','4','7','10','20')) AS close_with_reason_events
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (10,35)
    GROUP BY ph.postid
),
user_close_profile AS (
    SELECT
        p.owneruserid AS user_id,
        count(*) AS closed_posts,
        sum(COALESCE(p.score,0)) AS closed_posts_score_sum,
        count(*) FILTER (WHERE p.closeddate IS NOT NULL) AS closed_flagged,
        max(pce.last_close_at) AS last_close_event_at
    FROM posts p
    LEFT JOIN post_closure_events pce ON pce.postid = p.id
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
dupe_graph AS (
    SELECT
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        pl.linktypeid
    FROM postlinks pl
    WHERE pl.linktypeid = 3
),
user_dupe_metrics AS (
    SELECT
        COALESCE(p.owneruserid, rp.owneruserid) AS user_id,
        count(*) AS dup_links_involving_user,
        count(distinct CASE WHEN p.posttypeid = 1 THEN p.id WHEN rp.posttypeid = 1 THEN rp.id END) AS distinct_questions_involved
    FROM dupe_graph d
    LEFT JOIN posts p ON p.id = d.postid
    LEFT JOIN posts rp ON rp.id = d.relatedpostid
    GROUP BY COALESCE(p.owneruserid, rp.owneruserid)
),
activity_calendar AS (
    SELECT
        u.id AS user_id,
        CAST(d AS DATE) AS activity_date,
        COALESCE(pa.posts_on_day,0) AS posts_on_day,
        COALESCE(ca.comments_on_day,0) AS comments_on_day
    FROM users u
    CROSS JOIN LATERAL generate_series(date_trunc('month', (SELECT min(creationdate) FROM recent_users)), DATE '2024-10-01', INTERVAL '1 day') d
    LEFT JOIN LATERAL (
        SELECT count(*) AS posts_on_day
        FROM posts p
        WHERE p.owneruserid = u.id
          AND CAST(p.creationdate AS DATE) = CAST(d AS DATE)
    ) pa ON true
    LEFT JOIN LATERAL (
        SELECT count(*) AS comments_on_day
        FROM comments c
        WHERE c.userid = u.id
          AND CAST(c.creationdate AS DATE) = CAST(d AS DATE)
    ) ca ON true
),
calendar_rollup AS (
    SELECT
        user_id,
        sum(CASE WHEN extract(dow FROM activity_date) IN (1,2,3,4,5) THEN posts_on_day ELSE 0 END) AS wk_posts,
        sum(CASE WHEN extract(dow FROM activity_date) IN (0,6) THEN posts_on_day ELSE 0 END) AS we_posts,
        sum(comments_on_day) AS total_comments_period
    FROM activity_calendar
    GROUP BY user_id
),
user_titles AS (
    SELECT
        p.owneruserid AS user_id,
        avg(char_length(COALESCE(p.title,''))) FILTER (WHERE p.posttypeid = 1) AS avg_title_len,
        max(char_length(COALESCE(p.title,''))) FILTER (WHERE p.posttypeid = 1) AS max_title_len,
        min(NULLIF(char_length(COALESCE(p.title,'')),0)) FILTER (WHERE p.posttypeid = 1) AS min_nonzero_title_len
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
top_answers AS (
    SELECT
        p.owneruserid AS user_id,
        p.id AS post_id,
        p.score,
        row_number() OVER (PARTITION BY p.owneruserid ORDER BY p.score DESC NULLS LAST, p.id) AS rn
    FROM posts p
    WHERE p.posttypeid = 2
      AND p.owneruserid IS NOT NULL
),
top_answer_stats AS (
    SELECT
        ta.user_id,
        avg(ta.score) FILTER (WHERE ta.rn <= 3) AS avg_top3_answer_score,
        sum(CASE WHEN ta.rn <= 3 THEN 1 ELSE 0 END) AS top3_answers_count
    FROM top_answers ta
    GROUP BY ta.user_id
),
norms AS (
    SELECT
        avg(CAST(reputation AS numeric)) AS avg_rep,
        stddev_pop(CAST(reputation AS numeric)) AS sd_rep,
        avg(CAST(COALESCE(ua.q_count,0) AS numeric)) AS avg_q,
        stddev_pop(CAST(COALESCE(ua.q_count,0) AS numeric)) AS sd_q
    FROM recent_users ru
    LEFT JOIN user_activity ua ON ua.user_id = ru.user_id
),
user_ranked AS (
    SELECT
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        COALESCE(ua.q_count,0) AS q_count,
        COALESCE(ua.a_count,0) AS a_count,
        COALESCE(ua.post_score_sum,0) AS post_score_sum,
        COALESCE(ua.post_views_sum,0) AS post_views_sum,
        ca.comment_count,
        ba.badge_count,
        qa.answers_accepted,
        qt.tagged_sql_family_qs,
        uc.closed_posts,
        ud.dup_links_involving_user,
        cr.wk_posts,
        cr.we_posts,
        ut.avg_title_len,
        tas.avg_top3_answer_score,
        GREATEST(
            COALESCE(ua.last_post_at, TIMESTAMP '1970-01-01 00:00:00'),
            COALESCE(ca.last_comment_at, TIMESTAMP '1970-01-01 00:00:00'),
            COALESCE(ba.last_badge_at, TIMESTAMP '1970-01-01 00:00:00'),
            COALESCE(va.last_vote_at, TIMESTAMP '1970-01-01 00:00:00')
        ) AS last_seen_activity,
        CASE
            WHEN position('http' IN lower(COALESCE(ru.websiteurl,''))) = 1 THEN 'has_url'
            WHEN ru.websiteurl IS NULL OR ru.websiteurl = 'unknown' THEN 'no_url'
            ELSE 'other_url'
        END AS website_class,
        CASE WHEN ru.location ILIKE '%remote%' THEN 1 ELSE 0 END AS loc_remote_flag,
        CASE WHEN ru.reputation > 0 THEN ln(CAST(ru.reputation AS numeric)) ELSE NULL END AS rep_ln,
        (SELECT count(*) FROM posts p2 WHERE p2.owneruserid = ru.user_id AND p2.posttypeid = 2 AND p2.score > 0) AS pos_answer_count,
        (SELECT count(*) FROM comments c2 WHERE c2.userid = ru.user_id AND c2.score < 0) AS neg_comment_count
    FROM recent_users ru
    LEFT JOIN user_activity ua ON ua.user_id = ru.user_id
    LEFT JOIN comment_activity ca ON ca.user_id = ru.user_id
    LEFT JOIN badge_activity ba ON ba.user_id = ru.user_id
    LEFT JOIN vote_activity va ON va.user_id = ru.user_id
    LEFT JOIN qa_quality qa ON qa.user_id = ru.user_id
    LEFT JOIN question_tag_metrics qt ON qt.user_id = ru.user_id
    LEFT JOIN user_close_profile uc ON uc.user_id = ru.user_id
    LEFT JOIN user_dupe_metrics ud ON ud.user_id = ru.user_id
    LEFT JOIN calendar_rollup cr ON cr.user_id = ru.user_id
    LEFT JOIN user_titles ut ON ut.user_id = ru.user_id
    LEFT JOIN top_answer_stats tas ON tas.user_id = ru.user_id
),
scored AS (
    SELECT
        ur.*,
        COALESCE(ur.q_count,0) * 1.0
        + COALESCE(ur.a_count,0) * 2.0
        + COALESCE(ur.comment_count,0) * 0.25
        + COALESCE(ur.badge_count,0) * 0.5
        + COALESCE(ur.answers_accepted,0) * 3.0
        + COALESCE(ur.tagged_sql_family_qs,0) * 1.5
        + COALESCE(ur.closed_posts,0) * (-1.0)
        + COALESCE(ur.dup_links_involving_user,0) * (-0.5)
        + COALESCE(ur.wk_posts,0) * 0.2
        + COALESCE(ur.we_posts,0) * 0.3
        + COALESCE(ur.avg_top3_answer_score,0) * 1.0
        + COALESCE(ur.post_score_sum,0) * 0.1
        AS engagement_score,
        CASE
            WHEN COALESCE(ur.q_count,0) + COALESCE(ur.a_count,0) = 0 THEN NULL
            ELSE CAST(COALESCE(ur.post_score_sum,0) AS numeric) / NULLIF(CAST((COALESCE(ur.q_count,0) + COALESCE(ur.a_count,0)) AS numeric), 0)
        END AS avg_score_per_post,
        EXP(-EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - COALESCE(ur.last_seen_activity, TIMESTAMP '2024-10-01 12:34:56'))) / 86400.0 / 30.0) AS recency_weight
    FROM user_ranked ur
),
normalized AS (
    SELECT
        s.*,
        CASE
            WHEN n.sd_rep IS NULL OR n.sd_rep = 0 THEN NULL
            ELSE (s.reputation - n.avg_rep) / n.sd_rep
        END AS z_rep,
        CASE
            WHEN n.sd_q IS NULL OR n.sd_q = 0 THEN NULL
            ELSE (s.q_count - n.avg_q) / n.sd_q
        END AS z_q
    FROM scored s
    CROSS JOIN norms n
),
final_rank AS (
    SELECT
        *,
        (COALESCE(engagement_score,0) * COALESCE(recency_weight,1.0))
        + COALESCE(avg_score_per_post,0)
        + COALESCE(z_rep,0)
        + COALESCE(z_q,0)
        + CASE WHEN loc_remote_flag = 1 THEN 0.25 ELSE 0 END
        AS final_score,
        row_number() OVER (
            PARTITION BY cohort_month
            ORDER BY
                ((COALESCE(engagement_score,0) * COALESCE(recency_weight,1.0))
                 + COALESCE(avg_score_per_post,0)
                 + COALESCE(z_rep,0)
                 + COALESCE(z_q,0)
                 + CASE WHEN loc_remote_flag = 1 THEN 0.25 ELSE 0 END) DESC,
                user_id
        ) AS cohort_rank
    FROM normalized
)
SELECT
    fr.cohort_month,
    fr.cohort_rank,
    fr.user_id,
    COALESCE(NULLIF(fr.displayname,''), ('user#' || CAST(fr.user_id AS varchar))) AS displayname,
    fr.reputation,
    round(CAST(fr.final_score AS numeric), 3) AS final_score,
    fr.engagement_score,
    round(COALESCE(fr.avg_score_per_post,0), 3) AS avg_score_per_post,
    round(fr.recency_weight, 3) AS recency_weight,
    fr.q_count,
    fr.a_count,
    fr.comment_count,
    fr.badge_count,
    fr.answers_accepted,
    fr.tagged_sql_family_qs,
    fr.closed_posts,
    fr.dup_links_involving_user,
    fr.wk_posts,
    fr.we_posts,
    round(COALESCE(fr.avg_title_len,0), 1) AS avg_title_len,
    round(COALESCE(fr.avg_top3_answer_score,0),1) AS avg_top3_answer_score,
    fr.last_seen_activity,
    fr.website_class
FROM final_rank fr
WHERE fr.cohort_rank <= 50
   OR fr.final_score >= (
        SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY final_score)
        FROM final_rank
    )
ORDER BY fr.cohort_month DESC, fr.cohort_rank ASC, fr.final_score DESC;