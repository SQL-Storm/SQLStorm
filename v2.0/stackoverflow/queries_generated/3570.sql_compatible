WITH
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname                            AS display_name,
        u.reputation,
        COALESCE(bc.total_badges,0)               AS total_badges,
        COALESCE(qc.question_cnt,0)               AS question_cnt,
        COALESCE(ac.answer_cnt,0)                 AS answer_cnt,
        COALESCE(sc.avg_score,0)                  AS avg_score,
        ROW_NUMBER() OVER (ORDER BY u.reputation DESC) AS rank
    FROM users u
    LEFT JOIN (
        SELECT userid, COUNT(*) AS total_badges
        FROM badges
        GROUP BY userid
    ) bc ON bc.userid = u.id
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS question_cnt
        FROM posts
        WHERE posttypeid = 1
        GROUP BY owneruserid
    ) qc ON qc.owneruserid = u.id
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS answer_cnt
        FROM posts
        WHERE posttypeid = 2
        GROUP BY owneruserid
    ) ac ON ac.owneruserid = u.id
    LEFT JOIN (
        SELECT owneruserid, AVG(score) AS avg_score
        FROM posts
        WHERE score IS NOT NULL
        GROUP BY owneruserid
    ) sc ON sc.owneruserid = u.id
    WHERE u.reputation IS NOT NULL
),

recent_post AS (
    SELECT
        p.owneruserid,
        p.id               AS post_id,
        p.title,
        p.creationdate,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn
    FROM posts p
    WHERE p.posttypeid IN (1,2)
),

tag_pop AS (
    SELECT
        t.tagname,
        COUNT(p.id)                               AS post_cnt,
        SUM(p.score)                              AS total_score,
        MAX(p.creationdate)                       AS latest_use,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.id) DESC) AS tag_rank
    FROM tags t
    JOIN LATERAL (
        SELECT id, score, creationdate
        FROM posts
        WHERE tags LIKE '%' || '<' || t.tagname || '>' || '%'
    ) p ON true
    GROUP BY t.tagname
    HAVING COUNT(p.id) >= 10
),

set_union AS (
    SELECT
        user_id,
        display_name,
        reputation,
        total_badges,
        question_cnt,
        answer_cnt,
        avg_score,
        rank,
        CAST(NULL AS INTEGER)          AS post_id,
        CAST(NULL AS VARCHAR(300))     AS recent_title,
        CAST(NULL AS TIMESTAMP)        AS recent_date,
        CAST(NULL AS VARCHAR(35))      AS top_tag,
        CAST(NULL AS INTEGER)          AS tag_post_cnt,
        CAST(NULL AS BIGINT)           AS tag_total_score,
        NULL                            AS tag_rank
    FROM user_stats
    WHERE rank <= 50

    UNION ALL

    SELECT
        CAST(NULL AS INTEGER)           AS user_id,
        CAST(NULL AS VARCHAR(40))       AS display_name,
        CAST(NULL AS INTEGER)           AS reputation,
        CAST(NULL AS INTEGER)           AS total_badges,
        CAST(NULL AS INTEGER)           AS question_cnt,
        CAST(NULL AS INTEGER)           AS answer_cnt,
        CAST(NULL AS NUMERIC)           AS avg_score,
        CAST(NULL AS INTEGER)           AS rank,
        CAST(NULL AS INTEGER)           AS post_id,
        CAST(NULL AS TEXT)              AS recent_title,
        CAST(NULL AS TIMESTAMP)         AS recent_date,
        tp.tagname                      AS top_tag,
        tp.post_cnt                     AS tag_post_cnt,
        tp.total_score                  AS tag_total_score,
        tp.tag_rank                     AS tag_rank
    FROM tag_pop tp
    WHERE tp.tag_rank <= 50
)

SELECT *
FROM set_union
ORDER BY
    COALESCE(rank, 999999),
    COALESCE(tag_rank, 999999);