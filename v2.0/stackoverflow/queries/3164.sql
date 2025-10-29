WITH 
user_stats AS (
    SELECT 
        u.id                         AS user_id,
        u.displayname                AS display_name,
        u.reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1)          AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2)          AS answer_cnt,
        SUM(COALESCE(p.score,0))                            AS total_score,
        MAX(p.creationdate)                                AS last_post_dt
    FROM users u
    LEFT JOIN posts p
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),
badge_stats AS (
    SELECT 
        b.userid                     AS user_id,
        COUNT(*)                     AS badge_total,
        COUNT(*) FILTER (WHERE b.class = 1) AS gold_cnt,
        COUNT(*) FILTER (WHERE b.class = 2) AS silver_cnt,
        COUNT(*) FILTER (WHERE b.class = 3) AS bronze_cnt
    FROM badges b
    GROUP BY b.userid
),
tag_activity AS (
    SELECT 
        t.tagname,
        COUNT(p.id)                         AS tag_question_cnt,
        AVG(p.score)                        AS tag_avg_score,
        STRING_AGG(DISTINCT CAST(u.id AS text), ',') AS contributing_user_ids
    FROM tags t
    JOIN posts p
         ON p.tags LIKE '%' || '<' || t.tagname || '>' || '%'
    JOIN users u
         ON u.id = p.owneruserid
    WHERE p.posttypeid = 1
    GROUP BY t.tagname
),
ranked_users AS (
    SELECT 
        us.user_id,
        us.display_name,
        us.reputation,
        us.question_cnt,
        us.answer_cnt,
        us.total_score,
        bs.badge_total,
        ROW_NUMBER() OVER (ORDER BY us.reputation DESC, us.total_score DESC) AS rn
    FROM user_stats us
    LEFT JOIN badge_stats bs
           ON bs.user_id = us.user_id
    WHERE us.reputation > 1000 OR us.total_score > 500
),
main_rows AS (
SELECT 
    ru.rn                               AS rank,
    ru.display_name,
    ru.reputation,
    ru.question_cnt,
    ru.answer_cnt,
    ru.total_score,
    COALESCE(ru.badge_total,0)          AS badge_total,
    CASE 
        WHEN ru.question_cnt = 0 THEN NULL
        ELSE ROUND(CAST(ru.answer_cnt AS numeric) / ru.question_cnt, 2)
    END                                 AS answer_to_question_ratio,
    (SELECT COUNT(*) 
       FROM posts p 
      WHERE p.owneruserid = ru.user_id 
        AND p.creationdate >= DATE '2024-01-01')               AS recent_post_cnt,
    (SELECT MAX(v.creationdate) 
       FROM votes v 
      WHERE v.userid = ru.user_id)                             AS last_vote_dt,
    (SELECT STRING_AGG(DISTINCT t.tagname, ', ' ORDER BY t.tagname)
       FROM tags t
      WHERE EXISTS (SELECT 1 
                      FROM posts p2
                     WHERE p2.owneruserid = ru.user_id 
                       AND p2.posttypeid = 1 
                       AND p2.tags LIKE '%' || '<' || t.tagname || '>' || '%')
    )                                                 AS top_tags_used
FROM ranked_users ru
WHERE ru.rn <= 50
GROUP BY ru.rn, ru.display_name, ru.reputation, ru.question_cnt, ru.answer_cnt, ru.total_score, ru.badge_total, ru.user_id
ORDER BY ru.rn
)

SELECT * FROM main_rows

UNION ALL

SELECT 
    NULL      AS rank,
    '---'     AS display_name,
    NULL      AS reputation,
    NULL      AS question_cnt,
    NULL      AS answer_cnt,
    NULL      AS total_score,
    NULL      AS badge_total,
    NULL      AS answer_to_question_ratio,
    NULL      AS recent_post_cnt,
    NULL      AS last_vote_dt,
    NULL      AS top_tags_used
ORDER BY rank NULLS FIRST
LIMIT 100;