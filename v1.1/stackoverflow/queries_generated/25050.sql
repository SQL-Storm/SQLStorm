-- {"query": "25050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2134} 

/*  Complex performance‑benchmark query over the StackOverflow schema  */
WITH RECURSIVE
    /* 1️⃣ Aggregate per‑user post statistics  */
    user_stats AS (
        SELECT
            u.id                                            AS user_id,
            u.displayname                                   AS display_name,
            u.reputation,
            COALESCE(u.upvotes,0) - COALESCE(u.downvotes,0) AS net_votes,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1)    AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2)    AS answer_cnt,
            AVG(p.score) FILTER (WHERE p.posttypeid = 1)   AS avg_q_score,
            AVG(p.score) FILTER (WHERE p.posttypeid = 2)   AS avg_a_score,
            MAX(p.creationdate)                            AS last_post_dt
        FROM   users u
        LEFT   JOIN posts p ON p.owneruserid = u.id
        GROUP  BY u.id, u.displayname, u.reputation, u.upvotes, u.downvotes
    ),

    /* 2️⃣ Badge aggregates per user  */
    badge_counts AS (
        SELECT
            b.userid,
            SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            COUNT(*)                                      AS total_cnt
        FROM   badges b
        GROUP  BY b.userid
    ),

    /* 3️⃣ Expand tags from the Posts.Tags column (stored as “<tag1><tag2>…”) */
    tag_usage AS (
        SELECT
            p.owneruserid                                 AS user_id,
            UNNEST(string_to_array(trim(both '{}' FROM p.tags), '><')) AS tag,
            COUNT(*)                                      AS cnt
        FROM   posts p
        WHERE  p.tags IS NOT NULL
        GROUP  BY p.owneruserid, tag
    ),

    /* 4️⃣ Pick the most‑used tag per user */
    top_tag AS (
        SELECT
            tu.user_id,
            tu.tag,
            tu.cnt,
            ROW_NUMBER() OVER (PARTITION BY tu.user_id ORDER BY tu.cnt DESC, tu.tag) AS rn
        FROM   tag_usage tu
    ),

    /* 5️⃣ Recent vote activity (last 30 days) per user, pick the most common vote type */
    recent_votes AS (
        SELECT
            v.userid,
            vt.name                                 AS vote_type,
            COUNT(v.id)                             AS vote_cnt,
            ROW_NUMBER() OVER (PARTITION BY v.userid ORDER BY COUNT(v.id) DESC) AS rn
        FROM   votes v
        JOIN   votetypes vt ON vt.id = v.votetypeid
        WHERE  v.creationdate >= current_timestamp - INTERVAL '30 days'
        GROUP  BY v.userid, vt.name
    ),

    /* 6️⃣ Users that satisfy the “high‑rep” filter */
    qualified_users AS (
        SELECT us.*
        FROM   user_stats us
        WHERE  us.reputation > 10000
               AND (us.question_cnt + us.answer_cnt) > 0
    )

SELECT
    qu.user_id,
    qu.display_name,
    qu.reputation,
    qu.net_votes,
    qu.question_cnt,
    qu.answer_cnt,
    ROUND(qu.avg_q_score::numeric, 2)          AS avg_q_score,
    ROUND(qu.avg_a_score::numeric, 2)          AS avg_a_score,
    bc.gold_cnt,
    bc.silver_cnt,
    bc.bronze_cnt,
    bc.total_cnt,
    tt.tag                                      AS top_tag,
    tt.cnt                                      AS top_tag_cnt,
    rv.vote_type                                AS recent_top_vote,
    rv.vote_cnt                                 AS recent_top_vote_cnt,
    /*  votes per post ratio, guard against division by zero  */
    COALESCE(rv.vote_cnt,0)::float /
        NULLIF(qu.question_cnt + qu.answer_cnt,0) AS votes_per_post_ratio,
    qu.last_post_dt
FROM   qualified_users qu
LEFT   JOIN badge_counts bc      ON bc.userid = qu.user_id
LEFT   JOIN (SELECT user_id, tag, cnt FROM top_tag WHERE rn = 1) tt
                               ON tt.user_id = qu.user_id
LEFT   JOIN (SELECT userid, vote_type, vote_cnt FROM recent_votes WHERE rn = 1) rv
                               ON rv.userid = qu.user_id
WHERE  (bc.total_cnt IS NULL OR bc.total_cnt >= 5)      -- ensure some badge activity
UNION ALL
/* 7️⃣  Fallback slice: old low‑activity users (to increase row count & test UNION) */
SELECT
    u.id,
    u.displayname,
    u.reputation,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM   users u
WHERE  u.id NOT IN (SELECT user_id FROM qualified_users)
       AND u.creationdate < current_timestamp - INTERVAL '5 years'
ORDER  BY reputation DESC
LIMIT  100;
