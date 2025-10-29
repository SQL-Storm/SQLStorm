WITH recent_users AS (
    SELECT u.id AS user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'n/a') AS websiteurl_norm
    FROM users u
    WHERE u.creationdate >= (
        SELECT DATE_TRUNC('month', MAX(p.creationdate)) - INTERVAL '12 months' FROM posts p
    )
),
badge_rollup AS (
    SELECT b.userid,
           COUNT(*) AS badge_count,
           SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_count,
           SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_count,
           SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_count,
           MAX(b.date) AS last_badge_date
    FROM badges b
    GROUP BY b.userid
),
q AS (
    SELECT p.id,
           p.owneruserid AS user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate,
           p.favoritecount
    FROM posts p
    WHERE p.posttypeid = 1
),
a AS (
    SELECT p.id,
           p.parentid AS question_id,
           p.owneruserid AS user_id,
           p.creationdate,
           p.score
    FROM posts p
    WHERE p.posttypeid = 2
),
answers_agg AS (
    SELECT a.question_id,
           COUNT(*) AS answers_total,
           COUNT(*) FILTER (WHERE a.score > 0) AS answers_positive,
           MAX(a.score) AS max_answer_score,
           MIN(a.score) AS min_answer_score,
           AVG(CAST(a.score AS numeric)) AS avg_answer_score,
           MAX(a.creationdate) AS last_answer_date
    FROM a
    GROUP BY a.question_id
),
q_votes AS (
    SELECT v.postid AS question_id,
           SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
           SUM(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
           SUM(CASE WHEN v.votetypeid IN (8,9) THEN COALESCE(v.bountyamount,0) ELSE 0 END) AS bounty_total
    FROM votes v
    JOIN q ON q.id = v.postid
    GROUP BY v.postid
),
first_last_titles AS (
    SELECT ph.postid AS question_id,
           MIN(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (1,4)) AS first_title_edit,
           MAX(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (4,7)) AS last_title_edit
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (1,4,7)
    GROUP BY ph.postid
),
closure_reasons AS (
    SELECT ph.postid AS question_id,
           MAX(ph.creationdate) FILTER (WHERE ph.posthistorytypeid = 10) AS closed_when,
           MAX(ph.creationdate) FILTER (WHERE ph.posthistorytypeid = 11) AS reopened_when,
           MAX(CASE WHEN ph.posthistorytypeid = 10 THEN
                      CASE WHEN ph.comment ~ '^[0-9]+$' THEN ph.comment ELSE NULL END
                    END) AS close_reason_raw
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (10,11)
    GROUP BY ph.postid
),
duplicates AS (
    SELECT pl.postid AS dup_post_id,
           pl.relatedpostid AS canonical_id,
           MIN(pl.creationdate) AS first_link_date,
           COUNT(*) AS link_count
    FROM postlinks pl
    WHERE pl.linktypeid = 3
    GROUP BY pl.postid, pl.relatedpostid
),
tags_expanded AS (
    SELECT q.id AS question_id,
           UNNEST(string_to_array(SUBSTRING(q.tags FROM 2 FOR LENGTH(q.tags)-2), '><')) AS tag
    FROM q
    WHERE q.tags IS NOT NULL AND LENGTH(q.tags) > 2
),
tag_stats AS (
    SELECT te.question_id,
           COUNT(*) AS tag_count,
           SUM(CASE WHEN t.isrequired THEN 1 ELSE 0 END) AS required_tag_cnt,
           SUM(CASE WHEN t.ismoderatoronly THEN 1 ELSE 0 END) AS modonly_tag_cnt,
           SUM(COALESCE(t.count,0)) AS total_tag_usage
    FROM tags_expanded te
    LEFT JOIN tags t ON LOWER(t.tagname) = LOWER(te.tag)
    GROUP BY te.question_id
),
comment_sentiment AS (
    SELECT c.postid AS question_id,
           COUNT(*) AS comment_count,
           SUM(CASE WHEN c.score > 0 THEN 1 ELSE 0 END) AS pos_comments,
           SUM(CASE WHEN c.score < 0 THEN 1 ELSE 0 END) AS neg_comments,
           AVG(NULLIF(LENGTH(c.text),0)) AS avg_comment_len,
           MAX(c.creationdate) AS last_comment_date
    FROM comments c
    JOIN q ON q.id = c.postid
    GROUP BY c.postid
),
user_activity AS (
    SELECT p.owneruserid AS user_id,
           COUNT(*) FILTER (WHERE p.posttypeid = 1) AS q_count,
           COUNT(*) FILTER (WHERE p.posttypeid = 2) AS a_count,
           MAX(p.lastactivitydate) AS last_post_activity,
           SUM(COALESCE(p.score,0)) AS total_post_score
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
canonical_q AS (
    SELECT q.id AS question_id,
           CASE WHEN d.canonical_id IS NOT NULL THEN d.canonical_id ELSE q.id END AS canonical_id
    FROM q
    LEFT JOIN duplicates d ON d.dup_post_id = q.id
),
clusters AS (
    SELECT cq.canonical_id,
           COUNT(*) AS cluster_size,
           MIN(q.creationdate) AS cluster_first_created,
           MAX(q.creationdate) AS cluster_last_created,
           SUM(COALESCE(q.score,0)) AS cluster_score_sum
    FROM canonical_q cq
    JOIN q ON q.id = cq.question_id
    GROUP BY cq.canonical_id
),
question_metrics AS (
    SELECT
        q.id AS question_id,
        q.user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.closeddate,
        q.favoritecount,
        qa.answers_total,
        qa.answers_positive,
        qa.max_answer_score,
        qa.min_answer_score,
        qa.avg_answer_score,
        qv.upvotes,
        qv.downvotes,
        qv.favorites AS votes_favorites,
        qv.bounty_total,
        flt.first_title_edit,
        flt.last_title_edit,
        cr.closed_when,
        cr.reopened_when,
        cr.close_reason_raw,
        ts.tag_count,
        ts.required_tag_cnt,
        ts.modonly_tag_cnt,
        ts.total_tag_usage,
        cs.comment_count,
        cs.pos_comments,
        cs.neg_comments,
        cs.avg_comment_len,
        cs.last_comment_date,
        cq.canonical_id,
        cl.cluster_size,
        cl.cluster_first_created,
        cl.cluster_last_created,
        cl.cluster_score_sum
    FROM q
    LEFT JOIN answers_agg qa ON qa.question_id = q.id
    LEFT JOIN q_votes qv ON qv.question_id = q.id
    LEFT JOIN first_last_titles flt ON flt.question_id = q.id
    LEFT JOIN closure_reasons cr ON cr.question_id = q.id
    LEFT JOIN tag_stats ts ON ts.question_id = q.id
    LEFT JOIN comment_sentiment cs ON cs.question_id = q.id
    LEFT JOIN canonical_q cq ON cq.question_id = q.id
    LEFT JOIN clusters cl ON cl.canonical_id = cq.canonical_id
),
user_enriched AS (
    SELECT
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate AS user_created,
        ru.location,
        ru.websiteurl_norm,
        COALESCE(ba.badge_count,0) AS badge_count,
        COALESCE(ba.gold_count,0) AS gold_count,
        COALESCE(ba.silver_count,0) AS silver_count,
        COALESCE(ba.bronze_count,0) AS bronze_count,
        ba.last_badge_date,
        ua.q_count,
        ua.a_count,
        ua.last_post_activity,
        ua.total_post_score
    FROM recent_users ru
    LEFT JOIN badge_rollup ba ON ba.userid = ru.user_id
    LEFT JOIN user_activity ua ON ua.user_id = ru.user_id
),
ranked_questions AS (
    SELECT
        qm.question_id,
        qm.user_id,
        qm.creationdate,
        qm.score,
        qm.viewcount,
        qm.title,
        qm.tags,
        qm.answercount,
        qm.closeddate,
        qm.favoritecount,
        qm.answers_total,
        qm.answers_positive,
        qm.max_answer_score,
        qm.min_answer_score,
        qm.avg_answer_score,
        qm.upvotes,
        qm.downvotes,
        qm.votes_favorites,
        qm.bounty_total,
        qm.first_title_edit,
        qm.last_title_edit,
        qm.closed_when,
        qm.reopened_when,
        qm.close_reason_raw,
        qm.tag_count,
        qm.required_tag_cnt,
        qm.modonly_tag_cnt,
        qm.total_tag_usage,
        qm.comment_count,
        qm.pos_comments,
        qm.neg_comments,
        qm.avg_comment_len,
        qm.last_comment_date,
        qm.canonical_id,
        qm.cluster_size,
        qm.cluster_first_created,
        qm.cluster_last_created,
        qm.cluster_score_sum,
        ue.displayname,
        ue.reputation,
        ue.location,
        ue.websiteurl_norm,
        ue.badge_count,
        ue.gold_count,
        ue.silver_count,
        ue.bronze_count,
        ue.q_count,
        ue.a_count,
        ue.total_post_score,
        COALESCE(qm.upvotes,0) - COALESCE(qm.downvotes,0) AS net_votes,
        CASE WHEN qm.answercount IS NULL OR qm.answercount = 0 THEN 1 ELSE 0 END AS is_unanswered,
        CASE WHEN qm.closeddate IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
        CASE WHEN qm.closed_when IS NOT NULL AND qm.reopened_when IS NULL THEN 1 ELSE 0 END AS is_closed_only,
        CASE WHEN qm.closed_when IS NOT NULL AND qm.reopened_when IS NOT NULL THEN 1 ELSE 0 END AS is_reopened,
        CASE
          WHEN GREATEST(COALESCE(qm.viewcount,0),1) = 0 THEN 1
          ELSE LEAST(10, GREATEST(1,CEIL( (COALESCE(qm.viewcount,0) - 0 + 0.0) / NULLIF(GREATEST(COALESCE(qm.viewcount,0),1) - 0,0) * 10 )))
        END AS view_bucket_dynamic,
        NTILE(10) OVER (ORDER BY COALESCE(qm.viewcount,0) DESC NULLS LAST) AS view_ntile_desc,
        DENSE_RANK() OVER (ORDER BY COALESCE(qm.score,0) DESC, COALESCE(qm.viewcount,0) DESC) AS score_dense_rank,
        ROW_NUMBER() OVER (PARTITION BY ue.user_id ORDER BY COALESCE(qm.viewcount,0) DESC, qm.creationdate DESC) AS rn_per_user,
        SUM(COALESCE(qm.viewcount,0)) OVER (PARTITION BY ue.user_id) AS views_per_user_sum,
        AVG(COALESCE(qm.score,0)) OVER (PARTITION BY ue.user_id) AS avg_score_per_user,
        LAG(qm.creationdate) OVER (PARTITION BY ue.user_id ORDER BY qm.creationdate) AS prev_q_date,
        LEAD(qm.creationdate) OVER (PARTITION BY ue.user_id ORDER BY qm.creationdate) AS next_q_date
    FROM question_metrics qm
    LEFT JOIN user_enriched ue ON ue.user_id = qm.user_id
),
scored AS (
    SELECT
        rq.*,
        (
            COALESCE(rq.net_votes,0) * 2
          + COALESCE(rq.bounty_total,0) * 0.01
          + COALESCE(rq.viewcount,0) * 0.001
          + COALESCE(rq.answers_positive,0) * 1.5
          + CASE WHEN rq.is_unanswered = 1 THEN -5 ELSE 0 END
          + CASE WHEN rq.is_closed_only = 1 THEN -10 ELSE 0 END
          + CASE WHEN rq.is_reopened = 1 THEN 3 ELSE 0 END
          + LEAST(COALESCE(rq.tag_count,0), 5) * 0.5
          + COALESCE(rq.gold_count,0) * 0.2
          + COALESCE(rq.silver_count,0) * 0.1
          + COALESCE(rq.bronze_count,0) * 0.05
        ) AS perf_score
    FROM ranked_questions rq
),
topk AS (
    SELECT s.*
    FROM scored s
    JOIN (
       SELECT s2.question_id
       FROM scored s2
       ORDER BY s2.perf_score DESC NULLS LAST, COALESCE(s2.viewcount,0) DESC, s2.creationdate DESC
       LIMIT 500
    ) t ON t.question_id = s.question_id
),
null_logic_probe AS (
    SELECT
        t.question_id,
        CASE
            WHEN t.title IS NULL AND t.tags IS NULL THEN 'both_null'
            WHEN t.title IS NULL THEN 'title_null'
            WHEN t.tags IS NULL THEN 'tags_null'
            ELSE 'none_null'
        END AS null_case,
        COALESCE(NULLIF(TRIM(LOWER(t.title)), ''), '[no title]') AS title_norm,
        COALESCE(t.tags, '[no tags]') AS tags_norm
    FROM topk t
),
dupe_chains AS (
    SELECT
        cq.canonical_id,
        COUNT(DISTINCT cq.question_id) AS chain_len,
        MAX(q.creationdate) AS chain_last_created
    FROM canonical_q cq
    JOIN q ON q.id = cq.question_id
    GROUP BY cq.canonical_id
)
SELECT
    t.question_id,
    t.user_id,
    COALESCE(t.displayname, '[unknown]') AS owner_displayname,
    t.reputation,
    t.location,
    t.websiteurl_norm,
    t.creationdate AS question_created,
    t.score,
    t.viewcount,
    t.net_votes,
    t.answercount,
    t.answers_total,
    t.answers_positive,
    t.max_answer_score,
    t.min_answer_score,
    t.avg_answer_score,
    t.upvotes,
    t.downvotes,
    t.votes_favorites,
    t.bounty_total,
    t.closeddate,
    t.closed_when,
    t.reopened_when,
    t.close_reason_raw,
    t.tag_count,
    t.required_tag_cnt,
    t.modonly_tag_cnt,
    t.total_tag_usage,
    t.comment_count,
    t.pos_comments,
    t.neg_comments,
    t.avg_comment_len,
    t.last_comment_date,
    nlp.null_case,
    nlp.title_norm,
    nlp.tags_norm,
    t.canonical_id,
    t.cluster_size,
    t.cluster_first_created,
    t.cluster_last_created,
    t.cluster_score_sum,
    COALESCE(dc.chain_len,1) AS dupe_chain_len,
    dc.chain_last_created,
    t.view_bucket_dynamic,
    t.view_ntile_desc,
    t.score_dense_rank,
    t.rn_per_user,
    t.views_per_user_sum,
    t.avg_score_per_user,
    t.prev_q_date,
    t.next_q_date,
    t.badge_count,
    t.gold_count,
    t.silver_count,
    t.bronze_count,
    t.q_count,
    t.a_count,
    t.total_post_score,
    t.perf_score
FROM topk t
LEFT JOIN null_logic_probe nlp ON nlp.question_id = t.question_id
LEFT JOIN dupe_chains dc ON dc.canonical_id = t.canonical_id
WHERE (
    t.is_closed = 0
    OR (t.is_closed = 1 AND COALESCE(t.reopened_when, t.closed_when) >= t.creationdate)
)
AND (
    t.view_ntile_desc <= 9
    OR t.perf_score > (
        SELECT AVG(perf_score) FROM scored s
        WHERE s.creationdate >= (SELECT MIN(creationdate) FROM topk)
    )
)
ORDER BY t.perf_score DESC NULLS LAST, t.viewcount DESC NULLS LAST, t.creationdate DESC;