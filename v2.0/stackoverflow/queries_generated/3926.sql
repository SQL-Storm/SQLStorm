-- {"query": "3926.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1542} 

/*  Complex performance‑benchmark query on the StackOverflow schema  */
WITH
/* 1️⃣ Per‑user aggregated stats */
user_stats AS (
    SELECT
        u.id                                                    AS user_id,
        u.displayname                                            AS display_name,
        u.reputation,
        COUNT(b.id)                                              AS total_badges,
        SUM(CASE b.class WHEN 1 THEN 1 ELSE 0 END)               AS gold_badges,
        SUM(CASE b.class WHEN 2 THEN 1 ELSE 0 END)               AS silver_badges,
        SUM(CASE b.class WHEN 3 THEN 1 ELSE 0 END)               AS bronze_badges,
        COUNT(DISTINCT p.id)                                     AS distinct_posts,
        COUNT(DISTINCT c.id)                                     AS distinct_comments,
        COALESCE(MAX(p.lastactivitydate), TIMESTAMP '1970‑01‑01') AS last_activity
    FROM users u
    LEFT JOIN badges b   ON b.userid = u.id
    LEFT JOIN posts  p   ON p.owneruserid = u.id
    LEFT JOIN comments c ON c.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

/* 2️⃣ Recent activity (last 30 days) per user */
recent_activity AS (
    SELECT
        p.owneruserid                      AS user_id,
        COUNT(*) FILTER (WHERE p.creationdate >= CURRENT_DATE - INTERVAL '30 days') AS posts_last_30d,
        COUNT(*) FILTER (WHERE c.creationdate >= CURRENT_DATE - INTERVAL '30 days') AS comments_last_30d,
        COUNT(*) FILTER (WHERE v.creationdate >= CURRENT_DATE - INTERVAL '30 days' AND v.votetypeid = 2) AS upvotes_given_last_30d
    FROM posts    p
    FULL JOIN comments c ON c.userid = p.owneruserid
    FULL JOIN votes    v ON v.userid = p.owneruserid
    GROUP BY p.owneruserid
),

/* 3️⃣ Tag popularity snapshot */
popular_tags AS (
    SELECT
        t.tagname,
        t.count,
        ROW_NUMBER() OVER (ORDER BY t.count DESC) AS tag_rank
    FROM tags t
    WHERE t.count > 5000
),

/* 4️⃣ Detailed question‑post view with tag parsing */
question_details AS (
    SELECT
        p.id                                   AS post_id,
        p.title,
        p.score,
        p.viewcount,
        p.creationdate,
        COALESCE(NULLIF(p.tags, ''), '<>')      AS raw_tags,
        /* explode tag list into array, then count elements */
        CARDINALITY(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.tags), '><')) AS tag_cnt,
        /* flag if any tag matches a popular tag */
        EXISTS (
            SELECT 1
            FROM popular_tags pt
            WHERE pt.tagname = ANY (STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.tags), '><'))
        )                                       AS has_popular_tag,
        /* compute a “hotness” score using window functions */
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.score DESC, p.viewcount DESC) AS user_question_rank
    FROM posts p
    WHERE p.posttypeid = 1                      -- only questions
),

/* 5️⃣ Correlated sub‑query to detect “self‑answered” questions */
self_answered AS (
    SELECT
        q.post_id,
        q.title,
        q.tag_cnt,
        q.has_popular_tag,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM posts a
                WHERE a.parentid = q.post_id
                  AND a.owneruserid = (SELECT owneruserid FROM posts WHERE id = q.post_id)
                  AND a.posttypeid = 2                -- answers
            ) THEN TRUE
            ELSE FALSE
        END AS is_self_answered
    FROM question_details q
),

/* 6️⃣ Union of high‑scoring questions and top users */
high_score_questions AS (
    SELECT
        q.post_id          AS entity_id,
        q.title            AS description,
        q.score            AS metric,
        'question'         AS entity_type,
        q.owneruserid      AS owner_id
    FROM posts q
    WHERE q.posttypeid = 1
      AND q.score >= 100
),
top_users AS (
    SELECT
        us.user_id         AS entity_id,
        us.display_name    AS description,
        us.reputation      AS metric,
        'user'             AS entity_type,
        us.user_id         AS owner_id
    FROM user_stats us
    WHERE us.reputation >= 50000
)
SELECT *
FROM (
    SELECT * FROM high_score_questions
    UNION ALL
    SELECT * FROM top_users
) AS combined
-- final ordering with window function
QUALIFY ROW_NUMBER() OVER (PARTITION BY entity_type ORDER BY metric DESC) <= 10
ORDER BY entity_type, metric DESC;
