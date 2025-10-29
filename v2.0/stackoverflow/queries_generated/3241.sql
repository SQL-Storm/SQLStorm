-- {"query": "3241.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2567} 

/*  Benchmark query – combines CTEs, window functions, outer joins,
    correlated sub‑queries, set operators, complex predicates,
    string processing and NULL logic.                                          */
WITH
/* ---------------------------------------------------------------------- */
/*  1️⃣  Per‑user aggregated statistics                                    */
user_stats AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(u.views,0)                    AS total_views,

        /* badge counts by class */
        COUNT(b.id)        FILTER (WHERE b.class = 1) AS gold_badges,
        COUNT(b.id)        FILTER (WHERE b.class = 2) AS silver_badges,
        COUNT(b.id)        FILTER (WHERE b.class = 3) AS bronze_badges,

        /* number of questions and answers posted */
        (SELECT COUNT(*) FROM posts p
          WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS question_cnt,
        (SELECT COUNT(*) FROM posts p
          WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS answer_cnt,

        /* average score of answers (null → 0) */
        COALESCE( (SELECT AVG(p.score) FROM posts p
                    WHERE p.owneruserid = u.id
                      AND p.posttypeid = 2), 0)   AS avg_answer_score,

        /* most recent activity on any post owned by the user */
        MAX(p.lastactivitydate)                AS last_post_activity
    FROM users u
    LEFT JOIN badges  b ON b.userid = u.id
    LEFT JOIN posts   p ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation, u.views
),

/* ---------------------------------------------------------------------- */
/*  2️⃣  Recent activity per user (votes, comments, edits)                 */
recent_activity AS (
    SELECT
        u.id                                          AS user_id,
        MAX(v.creationdate)                           AS last_vote_dt,
        MAX(c.creationdate)                           AS last_comment_dt,
        MAX(ph.creationdate)                          AS last_edit_dt
    FROM users u
    LEFT JOIN votes       v  ON v.userid = u.id
    LEFT JOIN comments    c  ON c.userid = u.id
    LEFT JOIN posthistory ph ON ph.userid = u.id
    GROUP BY u.id
),

/* ---------------------------------------------------------------------- */
/*  3️⃣  Tag‑level aggregation (only question posts)                       */
tag_stats AS (
    SELECT
        t.tagname,
        COUNT(p.id)                              AS question_cnt,
        SUM(p.score)                             AS total_score,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.id) DESC) AS tag_rank
    FROM tags t
    JOIN LATERAL (
        SELECT p.id, p.score, p.tags
        FROM posts p
        WHERE p.posttypeid = 1                     -- only questions
          AND p.tags IS NOT NULL
    ) p ON TRUE
    /* split the '<tag1><tag2>' string into rows and match to tag name */
    JOIN LATERAL regexp_split_to_table(
            substring(p.tags FROM 2 FOR char_length(p.tags)-2),
            '><'
          ) AS split_tag(tag)
        ON split_tag.tag = t.tagname
    GROUP BY t.tagname
),

/* ---------------------------------------------------------------------- */
/*  4️⃣  Combine user aggregates with recent activity and tiering          */
combined_user AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.total_views,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.question_cnt,
        us.answer_cnt,
        us.avg_answer_score,
        us.last_post_activity,
        ra.last_vote_dt,
        ra.last_comment_dt,
        ra.last_edit_dt,

        /* tier based on reputation */
        CASE
            WHEN us.reputation >= 20000 THEN 'Legendary'
            WHEN us.reputation >= 10000 THEN 'Expert'
            WHEN us.reputation >=  5000 THEN 'Seasoned'
            ELSE                                 'Rising'
        END                                          AS reputation_tier,

        /* effective last activity – prefers any activity, fallback to now */
        COALESCE(
            GREATEST(
                us.last_post_activity,
                ra.last_vote_dt,
                ra.last_comment_dt,
                ra.last_edit_dt
            ),
            CURRENT_TIMESTAMP
        )                                            AS effective_last_activity
    FROM user_stats       us
    LEFT JOIN recent_activity ra ON ra.user_id = us.user_id
)

/* ---------------------------------------------------------------------- */
/*  Final result: two parts combined with UNION ALL                        */
SELECT
    cu.user_id,
    cu.displayname,
    cu.reputation,
    cu.reputation_tier,
    cu.total_views,
    cu.gold_badges,
    cu.silver_badges,
    cu.bronze_badges,
    cu.question_cnt,
    cu.answer_cnt,
    ROUND(cu.avg_answer_score,2)      AS avg_answer_score,
    cu.effective_last_activity,
    NULL::text                        AS extra_info        -- placeholder for union compatibility
FROM combined_user cu
WHERE ( cu.reputation_tier IN ('Expert','Legendary') )
   OR ( cu.gold_badges   >= 5 AND cu.avg_answer_score > 5 )
   OR ( cu.effective_last_activity > CURRENT_DATE - INTERVAL '30 days' )
ORDER BY cu.reputation DESC
LIMIT 100

UNION ALL

/* Separator row */
SELECT
    NULL, '--- Top 10 Tags ---', NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL,
    NULL,
    NULL
FROM (SELECT 1) s

UNION ALL

/* Top‑10 tag summary – re‑uses tag_stats CTE */
SELECT
    ts.tag_rank            AS user_id,               -- masquerade as “id” for union
    ts.tagname             AS displayname,
    NULL                   AS reputation,
    NULL                   AS reputation_tier,
    NULL                   AS total_views,
    NULL, NULL, NULL,
    ts.question_cnt        AS question_cnt,
    NULL                   AS answer_cnt,
    NULL                   AS avg_answer_score,
    ts.total_score         AS effective_last_activity,   -- reuse column slot
    NULL                   AS extra_info
FROM tag_stats ts
WHERE ts.tag_rank <= 10
ORDER BY user_id;
