WITH recent_posts AS (
    SELECT
        p.id,
        p.posttypeid,
        p.title,
        p.tags,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.closeddate,
        p.communityowneddate,
        COALESCE(u.displayname, p.ownerdisplayname) AS owner_name,
        u.reputation,
        u.location
    FROM posts p
    LEFT JOIN users u ON u.id = p.owneruserid
    WHERE p.creationdate >= (
        SELECT MAX(creationdate) - INTERVAL '365 days' FROM posts
    )
),
tag_expanded AS (
    SELECT
        rp.*,
        unnest(string_to_array(substring(rp.tags FROM 2 FOR length(rp.tags) - 2), '><')) AS tag
    FROM recent_posts rp
    WHERE rp.posttypeid = 1
),
tag_stats AS (
    SELECT
        te.tag,
        COUNT(*) AS tag_questions,
        AVG(CAST(te.score AS numeric)) AS avg_q_score,
        percentile_cont(0.9) WITHIN GROUP (ORDER BY te.viewcount) AS p90_views
    FROM tag_expanded te
    GROUP BY te.tag
),
answers AS (
    SELECT
        a.id,
        a.parentid,
        a.owneruserid,
        a.score,
        a.creationdate,
        row_number() OVER (PARTITION BY a.parentid ORDER BY a.score DESC, a.creationdate ASC, a.id ASC) AS rn_best_by_score,
        dense_rank() OVER (PARTITION BY a.parentid ORDER BY a.creationdate ASC) AS dr_first_answer,
        avg(a.score) OVER (PARTITION BY a.parentid) AS avg_answer_score_for_question
    FROM posts a
    WHERE a.posttypeid = 2
      AND a.creationdate >= (SELECT MAX(creationdate) - INTERVAL '365 days' FROM posts)
),
question_metrics AS (
    SELECT
        te.id AS question_id,
        te.title,
        te.tag,
        te.owneruserid AS q_ownerid,
        te.owner_name AS q_ownername,
        te.reputation AS q_owner_rep,
        te.score AS q_score,
        te.viewcount AS q_views,
        te.answercount AS q_answers,
        te.favoritecount AS q_favs,
        te.creationdate AS q_created,
        ts.tag_questions,
        ts.avg_q_score,
        ts.p90_views,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1 WHEN v.votetypeid = 3 THEN -1 ELSE 0 END) AS net_votes_last_year,
        COUNT(*) FILTER (WHERE v.votetypeid = 5) AS favorites_last_year
    FROM tag_expanded te
    LEFT JOIN tag_stats ts ON ts.tag = te.tag
    LEFT JOIN votes v
        ON v.postid = te.id
       AND v.creationdate >= te.creationdate
       AND v.creationdate < te.creationdate + INTERVAL '365 days'
       AND v.votetypeid IN (2,3,5)
    GROUP BY
        te.id, te.title, te.tag, te.owneruserid, te.owner_name, te.reputation,
        te.score, te.viewcount, te.answercount, te.favoritecount, te.creationdate,
        ts.tag_questions, ts.avg_q_score, ts.p90_views
),
first_and_best_answers AS (
    SELECT
        q.id AS question_id,
        q.acceptedanswerid,
        MIN(a.creationdate) AS first_answer_time,
        MIN(a.id) FILTER (WHERE a.dr_first_answer = 1) AS first_answer_id,
        MAX(a.score) AS best_answer_score,
        MIN(a.id) FILTER (WHERE a.rn_best_by_score = 1) AS best_answer_id,
        AVG(a.avg_answer_score_for_question) AS avg_ans_score
    FROM posts q
    LEFT JOIN answers a ON a.parentid = q.id
    WHERE q.posttypeid = 1
      AND q.creationdate >= (SELECT MAX(creationdate) - INTERVAL '365 days' FROM posts)
    GROUP BY q.id, q.acceptedanswerid
),
duplicates AS (
    SELECT
        pl.postid AS dup_question_id,
        COUNT(*) AS dup_count,
        MIN(pl.creationdate) AS first_dup_link_date,
        BOOL_OR(pl.linktypeid = 3) AS has_duplicate_links
    FROM postlinks pl
    WHERE pl.linktypeid IN (1,3)
    GROUP BY pl.postid
),
closure AS (
    SELECT
        ph.postid,
        MIN(ph.creationdate) AS first_closed_at,
        MAX(ph.creationdate) FILTER (WHERE ph.posthistorytypeid = 11) AS last_reopened_at,
        COUNT(*) FILTER (WHERE ph.posthistorytypeid = 10) AS close_events,
        COUNT(*) FILTER (WHERE ph.posthistorytypeid = 11) AS reopen_events,
        MAX(
            CASE
                WHEN ph.posthistorytypeid = 10 AND ph.comment ~ '^[0-9]+$' THEN CAST(ph.comment AS integer)
                ELSE NULL
            END
        ) AS last_close_reason_id
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (10,11)
    GROUP BY ph.postid
),
close_reason AS (
    SELECT
        c.postid,
        crt.name AS last_close_reason_name
    FROM closure c
    LEFT JOIN closeReasonTypes crt ON crt.id = c.last_close_reason_id
),
owner_activity AS (
    SELECT
        u.id AS ownerid,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS owner_q_count,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS owner_a_count,
        AVG(p.score) AS owner_avg_post_score,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY p.score) AS owner_median_post_score,
        SUM(COALESCE(p.viewcount,0)) FILTER (WHERE p.posttypeid = 1) AS owner_total_q_views
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    GROUP BY u.id
),
comment_engagement AS (
    SELECT
        c.postid,
        COUNT(*) AS comments_count,
        AVG(c.score) AS avg_comment_score,
        MAX(c.creationdate) AS last_comment_date,
        COUNT(*) FILTER (WHERE c.userid IS NULL) AS anon_comments
    FROM comments c
    GROUP BY c.postid
),
question_windowed AS (
    SELECT
        qm.question_id,
        qm.title,
        qm.tag,
        qm.q_ownerid,
        qm.q_ownername,
        qm.q_owner_rep,
        qm.q_score,
        qm.q_views,
        qm.q_answers,
        qm.q_favs,
        qm.q_created,
        qm.tag_questions,
        qm.avg_q_score,
        qm.p90_views,
        qm.net_votes_last_year,
        qm.favorites_last_year,
        faa.first_answer_time,
        faa.first_answer_id,
        faa.best_answer_id,
        faa.best_answer_score,
        faa.acceptedanswerid,
        faa.avg_ans_score,
        d.dup_count,
        d.first_dup_link_date,
        d.has_duplicate_links,
        c.first_closed_at,
        c.last_reopened_at,
        c.close_events,
        c.reopen_events,
        cr.last_close_reason_name,
        ca.comments_count,
        ca.avg_comment_score,
        ca.last_comment_date,
        ca.anon_comments,
        oa.owner_q_count,
        oa.owner_a_count,
        oa.owner_avg_post_score,
        oa.owner_median_post_score,
        oa.owner_total_q_views,
        COUNT(*) OVER (PARTITION BY qm.tag) AS questions_per_tag_window,
        row_number() OVER (PARTITION BY qm.tag ORDER BY qm.q_score DESC NULLS LAST, qm.q_views DESC NULLS LAST, qm.net_votes_last_year DESC NULLS LAST, qm.q_created ASC) AS rn_in_tag_by_popularity,
        SUM(qm.q_views) OVER (PARTITION BY qm.tag) AS sum_views_per_tag,
        AVG(qm.q_score) OVER (PARTITION BY qm.tag) AS avg_score_per_tag
    FROM question_metrics qm
    LEFT JOIN first_and_best_answers faa ON faa.question_id = qm.question_id
    LEFT JOIN duplicates d ON d.dup_question_id = qm.question_id
    LEFT JOIN closure c ON c.postid = qm.question_id
    LEFT JOIN close_reason cr ON cr.postid = qm.question_id
    LEFT JOIN comment_engagement ca ON ca.postid = qm.question_id
    LEFT JOIN owner_activity oa ON oa.ownerid = qm.q_ownerid
),
ranked AS (
    SELECT
        qw.*,
        CASE
            WHEN qw.acceptedanswerid IS NOT NULL THEN 'accepted'
            WHEN qw.best_answer_id IS NOT NULL THEN 'answered'
            ELSE 'unanswered'
        END AS answer_status,
        CASE
            WHEN qw.first_closed_at IS NOT NULL AND (qw.last_reopened_at IS NULL OR qw.first_closed_at > qw.last_reopened_at) THEN 'closed'
            WHEN qw.last_reopened_at IS NOT NULL THEN 'reopened'
            ELSE 'open'
        END AS closure_status,
        CASE WHEN qw.q_views >= qw.p90_views THEN 1 ELSE 0 END AS is_highly_viewed_for_tag,
        CASE WHEN qw.q_score >= COALESCE(qw.avg_score_per_tag, 0) THEN 1 ELSE 0 END AS is_above_avg_score_for_tag,
        COALESCE(qw.net_votes_last_year, 0) + COALESCE(qw.q_favs, 0) * 0.5 AS engagement_score,
        COALESCE(qw.q_score,0) * 2
            + LEAST(COALESCE(qw.q_views,0)/1000.0, 50)
            + COALESCE(qw.net_votes_last_year,0) * 1.5
            + CASE WHEN qw.acceptedanswerid IS NOT NULL THEN 10 WHEN qw.best_answer_id IS NOT NULL THEN 5 ELSE 0 END
            - CASE WHEN (CASE
                            WHEN qw.first_closed_at IS NOT NULL AND (qw.last_reopened_at IS NULL OR qw.first_closed_at > qw.last_reopened_at) THEN 'closed'
                            WHEN qw.last_reopened_at IS NOT NULL THEN 'reopened'
                            ELSE 'open'
                         END) = 'closed' THEN 8 ELSE 0 END
            - LEAST(COALESCE(qw.anon_comments,0) * 0.25, 5) AS composite_rank_score
    FROM question_windowed qw
),
final_set AS (
    SELECT
        r.*
    FROM ranked r
    WHERE
        (r.is_highly_viewed_for_tag = 1 OR r.is_above_avg_score_for_tag = 1)
        AND (r.closure_status <> 'closed' OR r.has_duplicate_links IS TRUE)
        AND (r.owner_q_count IS NULL OR r.owner_q_count >= 1)
    UNION ALL
    SELECT
        r.*
    FROM ranked r
    WHERE
        r.answer_status = 'unanswered'
        AND r.q_views > COALESCE(r.avg_score_per_tag, 0) * 100
)
SELECT
    fs.tag,
    fs.question_id,
    fs.title,
    fs.q_ownername,
    fs.q_owner_rep,
    fs.q_score,
    fs.q_views,
    fs.q_answers,
    fs.engagement_score,
    fs.composite_rank_score,
    fs.answer_status,
    fs.closure_status,
    COALESCE(fs.last_close_reason_name, 'N/A') AS last_close_reason_name,
    fs.comments_count,
    fs.avg_comment_score,
    fs.first_answer_id,
    fs.best_answer_id,
    CASE WHEN fs.acceptedanswerid = fs.best_answer_id AND fs.acceptedanswerid IS NOT NULL THEN 1 ELSE 0 END AS accepted_is_best_by_score,
    fs.dup_count,
    fs.has_duplicate_links,
    fs.rn_in_tag_by_popularity,
    rank() OVER (PARTITION BY fs.tag ORDER BY fs.composite_rank_score DESC, fs.engagement_score DESC, fs.q_created ASC, fs.question_id ASC) AS rank_in_tag_by_composite,
    dense_rank() OVER (ORDER BY fs.composite_rank_score DESC, fs.engagement_score DESC) AS global_dense_rank
FROM final_set fs
WHERE
    (fs.q_owner_rep IS NULL OR fs.q_owner_rep >= 1)
    AND (fs.q_views IS NOT NULL AND fs.q_views >= 0)
    AND (fs.tag IS NOT NULL AND fs.tag <> '')
ORDER BY
    fs.tag ASC,
    rank_in_tag_by_composite ASC,
    fs.question_id ASC
LIMIT 500;