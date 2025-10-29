-- {"query": "3792.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2331} 

/*  Complex performance‑benchmark query on the StackOverflow schema  */
WITH 
-- 1️⃣ Aggregate per user basic activity
user_stats AS (
    SELECT 
        u.id                                   AS user_id,
        u.displayname,
        COALESCE(u.reputation,0)               AS reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        AVG(p.score) FILTER (WHERE p.posttypeid IN (1,2)) AS avg_score,
        MAX(p.creationdate)                   AS last_post_dt
    FROM users u
    LEFT JOIN posts p 
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

-- 2️⃣ Badge totals per user (gold / silver / bronze)
badge_counts AS (
    SELECT 
        b.userid,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM badges b
    GROUP BY b.userid
),

-- 3️⃣ Votes per post (up / down) – used later for the top question
post_votes AS (
    SELECT 
        v.postid,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM votes v
    GROUP BY v.postid
),

-- 4️⃣ Extract tags from the <tag1><tag2> string and rank each user's questions
question_tags_ranked AS (
    SELECT 
        p.owneruserid,
        p.id                              AS post_id,
        p.title,
        p.score,
        p.creationdate,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid 
                           ORDER BY p.score DESC NULLS LAST,
                                    p.creationdate DESC) AS rn,
        /* split the raw <tag1><tag2> into rows, then re‑aggregate */
        STRING_AGG(t.tag, ',')            AS tags_csv
    FROM posts p
    LEFT JOIN LATERAL (
        SELECT UNNEST( STRING_TO_ARRAY( TRIM(BOTH '<>' FROM p.tags), '><' ) ) AS tag
    ) t ON true
    WHERE p.posttypeid = 1               -- only questions
    GROUP BY p.owneruserid, p.id, p.title, p.score, p.creationdate
),

-- 5️⃣ Pull the top‑ranked question for each user together with its vote totals
top_question AS (
    SELECT 
        q.owneruserid,
        q.post_id,
        q.title,
        q.tags_csv,
        COALESCE(v.up_votes,0)   AS up_votes,
        COALESCE(v.down_votes,0) AS down_votes
    FROM question_tags_ranked q
    LEFT JOIN post_votes v 
           ON v.postid = q.post_id
    WHERE q.rn = 1
),

-- 6️⃣ Correlated sub‑query to count how many of a user's posts beat their own average score
user_score_comparison AS (
    SELECT 
        us.user_id,
        (SELECT COUNT(*) 
         FROM posts p2 
         WHERE p2.owneruserid = us.user_id 
           AND p2.score > us.avg_score) AS posts_above_avg
    FROM user_stats us
)

-- 7️⃣ Final result set, mixing all the pieces together
SELECT 
    us.user_id,
    us.displayname,
    us.reputation,
    us.question_cnt,
    us.answer_cnt,
    ROUND(us.avg_score,2)                     AS avg_score,
    us.last_post_dt,
    COALESCE(bc.gold_badges,0)                AS gold_badges,
    COALESCE(bc.silver_badges,0)              AS silver_badges,
    COALESCE(bc.bronze_badges,0)              AS bronze_badges,
    tq.title                                  AS top_question_title,
    tq.tags_csv                               AS top_question_tags,
    tq.up_votes                               AS top_q_up_votes,
    tq.down_votes                             AS top_q_down_votes,
    uscmp.posts_above_avg                     AS posts_above_average,
    /* complex predicate using NULL logic */
    CASE 
        WHEN us.reputation IS NULL THEN 'NoRep'
        WHEN us.reputation < 0      THEN 'NegRep'
        ELSE 'PosRep' 
    END                                       AS rep_category
FROM user_stats us
LEFT JOIN badge_counts bc      ON bc.userid = us.user_id
LEFT JOIN top_question tq     ON tq.owneruserid = us.user_id
LEFT JOIN user_score_comparison uscmp ON uscmp.user_id = us.user_id
WHERE 
      (us.reputation > 1000 OR bc.gold_badges > 0)
  OR  (tq.up_votes > 10 AND tq.down_votes < 5)
ORDER BY us.reputation DESC NULLS LAST
LIMIT 100

UNION ALL

/* guaranteed at least one row when the above returns nothing */
SELECT 
    NULL AS user_id,
    NULL AS displayname,
    NULL AS reputation,
    NULL AS question_cnt,
    NULL AS answer_cnt,
    NULL AS avg_score,
    NULL AS last_post_dt,
    NULL AS gold_badges,
    NULL AS silver_badges,
    NULL AS bronze_badges,
    NULL AS top_question_title,
    NULL AS top_question_tags,
    NULL AS top_q_up_votes,
    NULL AS top_q_down_votes,
    NULL AS posts_above_average,
    'EmptySet' AS rep_category
WHERE NOT EXISTS (
      SELECT 1 
      FROM user_stats us
      LEFT JOIN badge_counts bc ON bc.userid = us.user_id
      LEFT JOIN top_question tq ON tq.owneruserid = us.user_id
      WHERE (us.reputation > 1000 OR bc.gold_badges > 0)
         OR (tq.up_votes > 10 AND tq.down_votes < 5)
);
