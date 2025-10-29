-- {"query": "3655.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2171} 

WITH 
/*--------------------------------------------------------------
  1. Aggregate each user’s posts and basic statistics
--------------------------------------------------------------*/
user_post_stats AS (
    SELECT 
        u.id                                         AS user_id,
        u.displayname                                 AS display_name,
        COUNT(p.id)                                   AS post_cnt,
        COALESCE(SUM(p.score),0)                      AS total_score,
        COALESCE(AVG(p.viewcount),0)                  AS avg_views,
        MAX(p.creationdate)                           AS last_post_dt,
        /* correlated sub‑query: total comments made by the user */
        (SELECT COUNT(*) FROM comments c WHERE c.userid = u.id) AS comment_cnt
    FROM users u
    LEFT JOIN posts p 
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname
),

/*--------------------------------------------------------------
  2. Concatenate badge names and count per class
--------------------------------------------------------------*/
badge_agg AS (
    SELECT 
        b.userid                                                  AS user_id,
        STRING_AGG(b.name, ', ')                                 AS badge_list,
        COUNT(*) FILTER (WHERE b.class = 1)                       AS gold_cnt,
        COUNT(*) FILTER (WHERE b.class = 2)                       AS silver_cnt,
        COUNT(*) FILTER (WHERE b.class = 3)                       AS bronze_cnt
    FROM badges b
    GROUP BY b.userid
),

/*--------------------------------------------------------------
  3. Vote totals per post (used later for the user’s top post)
--------------------------------------------------------------*/
post_votes AS (
    SELECT 
        v.postid,
        COUNT(*) FILTER (WHERE v.votetypeid = 2) AS up_votes,
        COUNT(*) FILTER (WHERE v.votetypeid = 3) AS down_votes
    FROM votes v
    GROUP BY v.postid
),

/*--------------------------------------------------------------
  4. The highest‑scoring question per user (window function)
--------------------------------------------------------------*/
top_question AS (
    SELECT 
        p.owneruserid                              AS user_id,
        p.id                                       AS post_id,
        p.score                                    AS post_score,
        ROW_NUMBER() OVER (
            PARTITION BY p.owneruserid 
            ORDER BY p.score DESC NULLS LAST, p.creationdate DESC
        )                                         AS rn
    FROM posts p
    WHERE p.posttypeid = 1          -- only questions
),

/*--------------------------------------------------------------
  5. Most recent activity recorded in PostHistory
--------------------------------------------------------------*/
recent_history AS (
    SELECT 
        ph.userid                                 AS user_id,
        MAX(ph.creationdate)                      AS last_history_dt
    FROM posthistory ph
    GROUP BY ph.userid
),

/*--------------------------------------------------------------
  6. Combine everything – left outer joins keep users with 
     missing pieces (e.g., no badges)
--------------------------------------------------------------*/
combined AS (
    SELECT 
        ups.user_id,
        ups.display_name,
        ups.post_cnt,
        ups.total_score,
        ups.avg_views,
        ups.last_post_dt,
        ups.comment_cnt,
        COALESCE(bag.badge_list, '')              AS badge_list,
        COALESCE(bag.gold_cnt,0)                  AS gold_cnt,
        COALESCE(bag.silver_cnt,0)                AS silver_cnt,
        COALESCE(bag.bronze_cnt,0)                AS bronze_cnt,
        rh.last_history_dt
    FROM user_post_stats ups
    LEFT JOIN badge_agg bag          ON bag.user_id = ups.user_id
    LEFT JOIN recent_history rh     ON rh.user_id = ups.user_id
),

/*--------------------------------------------------------------
  7. Users with NO posts but many badges (to be united later)
--------------------------------------------------------------*/
badge_only_users AS (
    SELECT 
        u.id                                   AS user_id,
        u.displayname                          AS display_name,
        0                                      AS post_cnt,
        0                                      AS total_score,
        0                                      AS avg_views,
        NULL                                   AS last_post_dt,
        0                                      AS comment_cnt,
        STRING_AGG(b.name, ', ')               AS badge_list,
        COUNT(*) FILTER (WHERE b.class = 1)    AS gold_cnt,
        COUNT(*) FILTER (WHERE b.class = 2)    AS silver_cnt,
        COUNT(*) FILTER (WHERE b.class = 3)    AS bronze_cnt,
        NULL                                   AS last_history_dt
    FROM users u
    JOIN badges b ON b.userid = u.id
    LEFT JOIN posts p ON p.owneruserid = u.id
    WHERE p.id IS NULL                       -- no posts at all
    GROUP BY u.id, u.displayname
)

--================================================================
-- Final result set (union of active contributors + badge‑only users)
--================================================================
SELECT
    c.user_id,
    c.display_name,
    c.post_cnt,
    c.total_score,
    ROUND(c.total_score::numeric / NULLIF(c.post_cnt,0),2)   AS avg_score_per_post,
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
WHERE c.post_cnt > 0                           -- keep only users with posts
  AND (c.gold_cnt > 0 OR c.total_score > 500)  -- filter for “interesting” users
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
ORDER BY total_score DESC NULLS LAST, gold_cnt DESC
LIMIT 200;
