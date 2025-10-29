-- {"query": "3061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2170} 

/*-----------------------------------------------------------------
   Performance‑benchmark query for the StackOverflow schema
   ---------------------------------------------------------
   - CTEs, window functions, outer joins, correlated subqueries
   - Set operators, complex predicates, string manipulation, NULL logic
-----------------------------------------------------------------*/

WITH
/* -----------------------------------------------------------------
   1️⃣  Aggregate per‑user basic activity
   ----------------------------------------------------------------- */
user_activity AS (
    SELECT
        u.id                                           AS user_id,
        u.displayname                                   AS display_name,
        u.reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1)    AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2)    AS answer_cnt,
        SUM(p.score)                                   AS total_score,
        MAX(p.creationdate)                            AS last_post_dt
    FROM users u
    LEFT JOIN posts p
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

/* -----------------------------------------------------------------
   2️⃣  Badge summary per user (including NULL handling)
   ----------------------------------------------------------------- */
user_badges AS (
    SELECT
        b.userid,
        COUNT(*)                                         AS badge_total,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END)     AS gold_cnt,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END)     AS silver_cnt,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END)     AS bronze_cnt
    FROM badges b
    GROUP BY b.userid
),

/* -----------------------------------------------------------------
   3️⃣  Vote aggregates per post (correlated to later join)
   ----------------------------------------------------------------- */
post_votes AS (
    SELECT
        v.postid,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(v.creationdate)                               AS last_vote_dt
    FROM votes v
    GROUP BY v.postid
),

/* -----------------------------------------------------------------
   4️⃣  Top‑scoring question per user (window function + string ops)
   ----------------------------------------------------------------- */
top_question_per_user AS (
    SELECT
        p.id                     AS post_id,
        p.owneruserid            AS owner_user_id,
        p.title,
        p.score,
        ROW_NUMBER() OVER (
            PARTITION BY p.owneruserid
            ORDER BY p.score DESC NULLS LAST,
                     p.creationdate DESC
        ) AS rn,
        /* Normalise tags – remove surrounding <> and replace >< with , */
        COALESCE(
            NULLIF(
                regexp_replace(
                    trim(both '<>' FROM p.tags),
                    '><',
                    ',',
                    'g'
                ),
                ''
            ),
            NULL
        ) AS tag_list
    FROM posts p
    WHERE p.posttypeid = 1           -- only questions
),

/* -----------------------------------------------------------------
   5️⃣  Recent close‑vote activity (using EXISTS and JSON extraction)
   ----------------------------------------------------------------- */
recent_closed AS (
    SELECT
        ph.postid,
        ph.creationdate AS closed_dt,
        CAST(ph.comment AS int) AS close_reason_id
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 10               -- Post Closed
      AND ph.creationdate >= now() - interval '60 days'
)

/* -----------------------------------------------------------------
   MAIN SELECT – combine everything, add derived columns,
   perform UNION ALL with a dummy set to exercise set operators.
   ----------------------------------------------------------------- */
SELECT
    ua.user_id,
    ua.display_name,
    ua.reputation,
    ua.question_cnt,
    ua.answer_cnt,
    ua.total_score,
    COALESCE(ub.badge_total, 0)      AS total_badges,
    COALESCE(ub.gold_cnt,   0)       AS gold_badges,
    COALESCE(ub.silver_cnt, 0)       AS silver_badges,
    COALESCE(ub.bronze_cnt, 0)       AS bronze_badges,
    tq.title                         AS top_question_title,
    tq.score                         AS top_question_score,
    pv.up_votes,
    pv.down_votes,
    (COALESCE(pv.up_votes,0) - COALESCE(pv.down_votes,0)) AS net_votes,
    CASE
        WHEN ua.reputation >= 20000 THEN 'Legendary'
        WHEN ua.reputation >= 10000 THEN 'Expert'
        WHEN ua.reputation >= 5000  THEN 'Experienced'
        ELSE 'Novice'
    END AS reputation_tier,
    CASE
        WHEN ua.last_post_dt IS NULL                     THEN 'NeverPosted'
        WHEN ua.last_post_dt < now() - interval '1 year' THEN 'Inactive'
        ELSE 'Active'
    END AS activity_status,
    rc.close_reason_id,
    rc.closed_dt
FROM user_activity ua
LEFT JOIN user_badges ub
       ON ub.userid = ua.user_id
LEFT JOIN top_question_per_user tq
       ON tq.owner_user_id = ua.user_id
      AND tq.rn = 1
LEFT JOIN post_votes pv
       ON pv.postid = tq.post_id
LEFT JOIN LATERAL (
    SELECT ph.close_reason_id, ph.closed_dt
    FROM recent_closed ph
    WHERE ph.postid = tq.post_id
    ORDER BY ph.closed_dt DESC
    LIMIT 1
) rc ON TRUE
WHERE ua.reputation IS NOT NULL          -- ensure deterministic output
ORDER BY ua.reputation DESC
LIMIT 100

UNION ALL

/* Dummy rows to stress set‑operator handling */
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL, NULL
FROM generate_series(1,5) gs(i);
