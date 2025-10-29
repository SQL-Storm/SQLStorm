-- {"query": "3655.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2171}
WITH 
user_post_stats AS (
    SELECT 
        u.id                                         AS user_id,
        u.displayname                                AS display_name,
        COUNT(p.id)                                  AS post_cnt,
        COALESCE(SUM(p.score),0)                     AS total_score,
        COALESCE(AVG(p.viewcount),0)                 AS avg_views,
        MAX(p.creationdate)                          AS last_post_dt,
        (SELECT COUNT(*) FROM comments c WHERE c.userid = u.id) AS comment_cnt
    FROM users u
    LEFT JOIN posts p 
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname
),
badge_agg AS (
    SELECT 
        b.userid                                       AS user_id,
        STRING_AGG(b.name, ', ')                       AS badge_list,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END)   AS gold_cnt,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END)   AS silver_cnt,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END)   AS bronze_cnt
    FROM badges b
    GROUP BY b.userid
),
post_votes AS (
    SELECT 
        v.postid,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM votes v
    GROUP BY v.postid
),
top_question AS (
    SELECT 
        p.owneruserid                                  AS user_id,
        p.id                                           AS post_id,
        p.score                                        AS post_score,
        ROW_NUMBER() OVER (
            PARTITION BY p.owneruserid 
            ORDER BY p.score DESC, p.creationdate DESC
        )                                              AS rn
    FROM posts p
    WHERE p.posttypeid = 1
),
recent_history AS (
    SELECT 
        ph.userid                                      AS user_id,
        MAX(ph.creationdate)                           AS last_history_dt
    FROM posthistory ph
    GROUP BY ph.userid
),
combined AS (
    SELECT 
        ups.user_id,
        ups.display_name,
        ups.post_cnt,
        ups.total_score,
        ups.avg_views,
        ups.last_post_dt,
        ups.comment_cnt,
        COALESCE(bag.badge_list, '')                   AS badge_list,
        COALESCE(bag.gold_cnt,0)                       AS gold_cnt,
        COALESCE(bag.silver_cnt,0)                     AS silver_cnt,
        COALESCE(bag.bronze_cnt,0)                     AS bronze_cnt,
        rh.last_history_dt
    FROM user_post_stats ups
    LEFT JOIN badge_agg bag          ON bag.user_id = ups.user_id
    LEFT JOIN recent_history rh     ON rh.user_id = ups.user_id
),
badge_only_users AS (
    SELECT 
        u.id                                           AS user_id,
        u.displayname                                  AS display_name,
        0                                              AS post_cnt,
        0                                              AS total_score,
        0                                              AS avg_views,
        CAST(NULL AS timestamp)                        AS last_post_dt,
        0                                              AS comment_cnt,
        STRING_AGG(b.name, ', ')                       AS badge_list,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END)   AS gold_cnt,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END)   AS silver_cnt,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END)   AS bronze_cnt,
        CAST(NULL AS timestamp)                        AS last_history_dt
    FROM users u
    JOIN badges b ON b.userid = u.id
    LEFT JOIN posts p ON p.owneruserid = u.id
    WHERE p.id IS NULL
    GROUP BY u.id, u.displayname
)
SELECT
    c.user_id,
    c.display_name,
    c.post_cnt,
    c.total_score,
    ROUND(CAST(c.total_score AS numeric) / NULLIF(c.post_cnt,0),2)   AS avg_score_per_post,
    c.avg_views,
    c.comment_cnt,
    c.gold_cnt,
    c.silver_cnt,
    c.bronze_cnt,
    c.badge_list,
    c.last_post_dt,
    c.last_history_dt,
    tq.post_id            AS top_question_id,
    tq.post_score         AS top_question_score,
    pv.up_votes,
    pv.down_votes
FROM combined c
LEFT JOIN top_question tq
       ON tq.user_id = c.user_id AND tq.rn = 1
LEFT JOIN post_votes pv
       ON pv.postid = tq.post_id
WHERE c.post_cnt > 0
  AND (c.gold_cnt > 0 OR c.total_score > 500)
UNION ALL
SELECT
    bo.user_id,
    bo.display_name,
    bo.post_cnt,
    bo.total_score,
    NULL                                          AS avg_score_per_post,
    bo.avg_views,
    bo.comment_cnt,
    bo.gold_cnt,
    bo.silver_cnt,
    bo.bronze_cnt,
    bo.badge_list,
    bo.last_post_dt,
    bo.last_history_dt,
    NULL                                          AS top_question_id,
    NULL                                          AS top_question_score,
    NULL                                          AS up_votes,
    NULL                                          AS down_votes
FROM badge_only_users bo
WHERE bo.gold_cnt > 0 OR bo.silver_cnt > 0
ORDER BY total_score DESC, gold_cnt DESC
LIMIT 200;