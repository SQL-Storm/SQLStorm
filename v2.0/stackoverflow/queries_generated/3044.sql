-- {"query": "3044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2055} 

/*  Complex benchmark query using CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string handling and NULL logic   */
WITH
    /* 1️⃣ Aggregate user reputation and badge counts */
    user_stats AS (
        SELECT
            u.id                                    AS user_id,
            u.displayname,
            u.reputation,
            COALESCE(u.location, 'Unknown')          AS location,
            COUNT(b.id) FILTER (WHERE b.class = 1)   AS gold_badges,
            COUNT(b.id) FILTER (WHERE b.class = 2)   AS silver_badges,
            COUNT(b.id) FILTER (WHERE b.class = 3)   AS bronze_badges
        FROM users u
        LEFT JOIN badges b ON b.userid = u.id
        GROUP BY u.id, u.displayname, u.reputation, u.location
    ),

    /* 2️⃣ Recent question posts (last 180 days) with row numbers per user */
    recent_questions AS (
        SELECT
            p.owneruserid                         AS user_id,
            p.id                                   AS post_id,
            p.creationdate,
            p.title,
            p.tags,
            p.score,
            p.viewcount,
            p.answercount,
            ROW_NUMBER() OVER (
                PARTITION BY p.owneruserid
                ORDER BY p.creationdate DESC
            )                                      AS rn
        FROM posts p
        WHERE p.posttypeid = 1                         -- only questions
          AND p.creationdate > CURRENT_DATE - INTERVAL '180 days'
    ),

    /* 3️⃣ Answer statistics per question (total answers, accepted answers) */
    answer_stats AS (
        SELECT
            a.parentid                              AS question_id,
            COUNT(*)                                AS total_answers,
            SUM(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS accepted_answers
        FROM posts a
        JOIN posts q ON q.id = a.parentid AND q.posttypeid = 1
        WHERE a.posttypeid = 2                         -- only answers
        GROUP BY a.parentid
    ),

    /* 4️⃣ Vote aggregation (net score = upvotes - downvotes) */
    vote_agg AS (
        SELECT
            v.postid,
            SUM(CASE
                    WHEN v.votetypeid = 2 THEN 1    -- upvote
                    WHEN v.votetypeid = 3 THEN -1   -- downvote
                    ELSE 0
                END)                                 AS net_votes
        FROM votes v
        GROUP BY v.postid
    ),

    /* 5️⃣ Correlated sub‑query to fetch the latest edit date per post (may be NULL) */
    latest_edit AS (
        SELECT
            ph.postid,
            MAX(ph.creationdate) AS last_edit
        FROM posthistory ph
        WHERE ph.posthistorytypeid IN (4,5,6)          -- edits of title/body/tags
        GROUP BY ph.postid
    )

/* ==================== MAIN SELECT ==================== */
SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.location,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    rq.post_id,
    rq.title,
    rq.creationdate          AS post_date,
    rq.score                 AS original_score,
    COALESCE(va.net_votes,0) AS net_vote_score,
    rq.viewcount,
    rq.answercount,
    COALESCE(as.total_answers,0)   AS total_answers,
    COALESCE(as.accepted_answers,0) AS accepted_answers,
    LEAST(rq.rn,5)                AS recent_rank,
    /* Engagement metric using NULL‑safe arithmetic */
    CASE
        WHEN rq.answercount IS NULL OR rq.answercount = 0 THEN NULL
        ELSE (rq.score * COALESCE(rq.viewcount,0)) / NULLIF(rq.answercount,0)
    END                           AS engagement_score,
    le.last_edit
FROM user_stats us
LEFT JOIN recent_questions rq
       ON rq.user_id = us.user_id
      AND rq.rn <= 5                               -- keep only top‑5 recent per user
LEFT JOIN vote_agg va
       ON va.postid = rq.post_id
LEFT JOIN answer_stats as
       ON as.question_id = rq.post_id
LEFT JOIN latest_edit le
       ON le.postid = rq.post_id
WHERE (us.reputation > 5000 OR us.gold_badges > 0)  -- filter interesting users
  AND (rq.tags IS NOT NULL AND rq.tags <> '')
/* ==================== UNION ALL ==================== */
/* Users without recent questions – still show badge summary */
UNION ALL
SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.location,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    NULL AS post_id,
    NULL AS title,
    NULL AS post_date,
    NULL AS original_score,
    NULL AS net_vote_score,
    NULL AS viewcount,
    NULL AS answercount,
    NULL AS total_answers,
    NULL AS accepted_answers,
    NULL AS recent_rank,
    NULL AS engagement_score,
    NULL AS last_edit
FROM user_stats us
WHERE NOT EXISTS (
    SELECT 1 FROM recent_questions rq WHERE rq.user_id = us.user_id
)
ORDER BY reputation DESC, gold_badges DESC, user_id
LIMIT 100;
