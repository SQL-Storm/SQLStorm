-- {"query": "3334.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2180} 

WITH
    /* 1️⃣  Gather basic per‑user post statistics */
    user_stats AS (
        SELECT
            u.id                                   AS user_id,
            u.displayname,
            u.reputation,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1)            AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2)            AS answer_cnt,
            SUM(p.score) FILTER (WHERE p.posttypeid = 1)           AS question_score_sum,
            SUM(p.score) FILTER (WHERE p.posttypeid = 2)           AS answer_score_sum,
            COALESCE(SUM(CASE WHEN v.votetypeid = 2 THEN 1 END),0) AS upvotes_received,
            COALESCE(SUM(CASE WHEN v.votetypeid = 3 THEN 1 END),0) AS downvotes_received
        FROM users u
        LEFT JOIN posts   p ON p.owneruserid = u.id
        LEFT JOIN votes   v ON v.postid = p.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    /* 2️⃣  Count badges per class */
    badge_counts AS (
        SELECT
            b.userid,
            COUNT(*) FILTER (WHERE b.class = 1) AS gold_badges,
            COUNT(*) FILTER (WHERE b.class = 2) AS silver_badges,
            COUNT(*) FILTER (WHERE b.class = 3) AS bronze_badges
        FROM badges b
        GROUP BY b.userid
    ),

    /* 3️⃣  Determine the most recent activity of each user */
    recent_activity AS (
        SELECT
            u.id                                            AS user_id,
            MAX(p.creationdate)                             AS last_post_dt,
            MAX(c.creationdate)                             AS last_comment_dt,
            MAX(v.creationdate)                             AS last_vote_dt
        FROM users u
        LEFT JOIN posts    p ON p.owneruserid = u.id
        LEFT JOIN comments c ON c.userid = u.id
        LEFT JOIN votes    v ON v.userid = u.id
        GROUP BY u.id
    ),

    /* 4️⃣  Rank users by reputation and assign row numbers inside “high / low” buckets */
    user_ranking AS (
        SELECT
            us.*,
            RANK()     OVER (ORDER BY us.reputation DESC)                      AS rep_rank,
            ROW_NUMBER() OVER (
                PARTITION BY CASE WHEN us.reputation >= 10000 THEN 'high' ELSE 'low' END
                ORDER BY us.answer_cnt DESC
            )                                                                    AS rn_in_bucket
        FROM user_stats us
    ),

    /* 5️⃣  Count how many of a user's questions are tagged with “sql” (using string functions) */
    sql_tag_counts AS (
        SELECT
            p.owneruserid                          AS user_id,
            COUNT(*)                               AS sql_question_cnt
        FROM posts p
        WHERE p.posttypeid = 1                                            -- only questions
          AND p.tags IS NOT NULL
          AND EXISTS (
                SELECT 1
                FROM unnest(
                         string_to_array(
                             substring(p.tags, 2, length(p.tags)-2),   -- strip leading/trailing < >
                             '><'
                         )
                     ) AS t(tag)
                WHERE t.tag = 'sql'
          )
        GROUP BY p.owneruserid
    )

/* ==============================
   FINAL RESULT (unioned with a placeholder row for benchmarking set‑operator cost)
   ============================== */
SELECT
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.question_cnt,
    ur.answer_cnt,
    ur.question_score_sum,
    ur.answer_score_sum,
    ur.upvotes_received,
    ur.downvotes_received,
    COALESCE(bc.gold_badges,   0) AS gold_badges,
    COALESCE(bc.silver_badges, 0) AS silver_badges,
    COALESCE(bc.bronze_badges, 0) AS bronze_badges,
    ra.last_post_dt,
    ra.last_comment_dt,
    ra.last_vote_dt,
    ur.rep_rank,
    ur.rn_in_bucket,
    CASE
        WHEN ur.question_cnt = 0 THEN NULL
        ELSE ROUND(ur.answer_cnt::numeric / NULLIF(ur.question_cnt,0), 2)
    END AS answer_to_question_ratio,
    COALESCE(stc.sql_question_cnt, 0) AS sql_tag_question_cnt
FROM user_ranking   ur
LEFT JOIN badge_counts    bc  ON bc.userid = ur.user_id
LEFT JOIN recent_activity ra  ON ra.user_id = ur.user_id
LEFT JOIN sql_tag_counts  stc ON stc.user_id = ur.user_id
WHERE (ur.rep_rank <= 1000 OR ur.answer_cnt > 50)

/* UNION ALL to force the optimizer to handle a set operator */
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL
FROM (SELECT 1) dummy
WHERE NOT EXISTS (SELECT 1 FROM users WHERE reputation > 20000);
