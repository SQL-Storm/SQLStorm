-- {"query": "3115.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1716} 

WITH 
-- Base statistics per user
user_stats AS (
    SELECT 
        u.id                                               AS user_id,
        COALESCE(u.displayname, 'Anonymous')                AS display_name,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        COUNT(DISTINCT b.id)                                AS total_badges,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END)       AS gold_badges,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END)       AS silver_badges,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END)       AS bronze_badges,
        COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        AVG(CASE WHEN p.posttypeid = 1 THEN p.score END)    AS avg_q_score,
        AVG(CASE WHEN p.posttypeid = 2 THEN p.score END)    AS avg_a_score,
        COUNT(DISTINCT v.id) FILTER (WHERE v.votetypeid = 2) AS upvote_cnt,
        COUNT(DISTINCT v.id) FILTER (WHERE v.votetypeid = 3) AS downvote_cnt
    FROM users u
    LEFT JOIN badges b   ON b.userid = u.id
    LEFT JOIN posts  p   ON p.owneruserid = u.id
    LEFT JOIN votes  v   ON v.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
),

-- Recent activity per user (correlated subquery)
recent_activity AS (
    SELECT 
        u.id                                        AS user_id,
        (SELECT MAX(p.creationdate) 
         FROM posts p 
         WHERE p.owneruserid = u.id)               AS last_post_date,
        (SELECT MAX(c.creationdate) 
         FROM comments c 
         WHERE c.userid = u.id)                    AS last_comment_date
    FROM users u
),

-- Top tags a user has contributed to (using string aggregation)
user_top_tags AS (
    SELECT 
        p.owneruserid                               AS user_id,
        STRING_AGG(DISTINCT t.tagname, ', ') 
            FILTER (WHERE t.tagname IS NOT NULL)    AS tags_used,
        COUNT(*)                                    AS tag_appearances
    FROM posts p
    JOIN LATERAL (
        SELECT regexp_split_to_table(p.tags, '[><]+') AS raw_tag
    ) AS split_tag ON TRUE
    LEFT JOIN tags t ON t.tagname = split_tag.raw_tag
    WHERE p.posttypeid = 1                          -- only questions
      AND p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),

-- Users with at least one accepted answer (correlated existence check)
users_with_accepted AS (
    SELECT DISTINCT 
        a.owneruserid                               AS user_id
    FROM posts a
    WHERE a.posttypeid = 2                           -- answers
      AND EXISTS (
            SELECT 1 
            FROM posts q 
            WHERE q.id = a.parentid 
              AND q.acceptedanswerid = a.id
        )
),

-- Union of two sets: high‑reputation active users + low‑reputation users with badges
unioned_users AS (
    SELECT us.user_id, us.display_name, us.reputation
    FROM user_stats us
    JOIN recent_activity ra   ON ra.user_id = us.user_id
    WHERE us.reputation >= 20000
      AND COALESCE(ra.last_post_date, ra.last_comment_date) > (CURRENT_DATE - INTERVAL '30 days')
    
    UNION ALL
    
    SELECT us.user_id, us.display_name, us.reputation
    FROM user_stats us
    LEFT JOIN badges b        ON b.userid = us.user_id
    WHERE us.reputation < 1000
      AND b.id IS NOT NULL
)

SELECT 
    uu.user_id,
    uu.display_name,
    uu.reputation,
    us.total_badges,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.question_cnt,
    us.answer_cnt,
    ROUND(us.avg_q_score::numeric,2) AS avg_question_score,
    ROUND(us.avg_a_score::numeric,2) AS avg_answer_score,
    us.upvote_cnt,
    us.downvote_cnt,
    COALESCE(ra.last_post_date, ra.last_comment_date)          AS most_recent_activity,
    COALESCE(ut.tags_used, '')                               AS top_tags,
    CASE 
        WHEN uwa.user_id IS NOT NULL THEN 'Has Accepted Answer'
        ELSE 'No Accepted Answer'
    END                                                       AS accepted_answer_status,
    ROW_NUMBER() OVER (PARTITION BY uu.reputation >= 20000 
                       ORDER BY us.reputation DESC, us.total_badges DESC) AS rank_in_group
FROM unioned_users uu
JOIN user_stats us          ON us.user_id = uu.user_id
LEFT JOIN recent_activity ra ON ra.user_id = uu.user_id
LEFT JOIN user_top_tags ut   ON ut.user_id = uu.user_id
LEFT JOIN users_with_accepted uwa ON uwa.user_id = uu.user_id
WHERE (us.question_cnt + us.answer_cnt) > 0
  AND (us.reputation IS NOT NULL AND us.reputation <> 0)
ORDER BY uu.reputation DESC, rank_in_group;
