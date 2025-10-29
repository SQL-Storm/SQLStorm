-- {"query": "3792.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2331}
WITH 
user_stats AS (
    SELECT 
        u.id                                   AS user_id,
        u.displayname,
        COALESCE(u.reputation, 0)               AS reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        AVG(p.score) FILTER (WHERE p.posttypeid IN (1,2)) AS avg_score,
        MAX(p.creationdate)                   AS last_post_dt
    FROM users u
    LEFT JOIN posts p 
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

badge_counts AS (
    SELECT 
        b.userid,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges
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

question_tags_ranked AS (
    SELECT 
        p.owneruserid,
        p.id                              AS post_id,
        p.title,
        p.score,
        p.creationdate,
        ROW_NUMBER() OVER (
            PARTITION BY p.owneruserid 
            ORDER BY p.score DESC NULLS LAST, p.creationdate DESC
        ) AS rn,
        STRING_AGG(t.tag, ',')            AS tags_csv
    FROM posts p
    LEFT JOIN LATERAL (
        SELECT UNNEST( STRING_TO_ARRAY( TRIM(BOTH '<>' FROM p.tags), '><' ) ) AS tag
    ) t ON TRUE
    WHERE p.posttypeid = 1
    GROUP BY p.owneruserid, p.id, p.title, p.score, p.creationdate
),

top_question AS (
    SELECT 
        q.owneruserid,
        q.post_id,
        q.title,
        q.tags_csv,
        COALESCE(v.up_votes, 0)   AS up_votes,
        COALESCE(v.down_votes, 0) AS down_votes
    FROM question_tags_ranked q
    LEFT JOIN post_votes v 
           ON v.postid = q.post_id
    WHERE q.rn = 1
),

user_score_comparison AS (
    SELECT 
        us.user_id,
        (
         SELECT COUNT(*) 
         FROM posts p2 
         WHERE p2.owneruserid = us.user_id 
           AND p2.score > us.avg_score
        ) AS posts_above_avg
    FROM user_stats us
)

SELECT *
FROM (
    SELECT 
        us.user_id,
        us.displayname,
        us.reputation,
        us.question_cnt,
        us.answer_cnt,
        ROUND(CAST(us.avg_score AS numeric), 2)                     AS avg_score,
        us.last_post_dt,
        COALESCE(bc.gold_badges, 0)                AS gold_badges,
        COALESCE(bc.silver_badges, 0)              AS silver_badges,
        COALESCE(bc.bronze_badges, 0)              AS bronze_badges,
        tq.title                                  AS top_question_title,
        tq.tags_csv                               AS top_question_tags,
        tq.up_votes                               AS top_q_up_votes,
        tq.down_votes                             AS top_q_down_votes,
        uscmp.posts_above_avg                     AS posts_above_average,
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
          (us.reputation > 1000 OR COALESCE(bc.gold_badges, 0) > 0)
      OR  (COALESCE(tq.up_votes, 0) > 10 AND COALESCE(tq.down_votes, 0) < 5)
    ORDER BY us.reputation DESC NULLS LAST
    LIMIT 100
) main_result

UNION ALL

SELECT 
    CAST(NULL AS bigint)      AS user_id,
    CAST(NULL AS text)        AS displayname,
    CAST(NULL AS numeric)     AS reputation,
    CAST(NULL AS integer)     AS question_cnt,
    CAST(NULL AS integer)     AS answer_cnt,
    CAST(NULL AS numeric)     AS avg_score,
    CAST(NULL AS timestamp)   AS last_post_dt,
    CAST(NULL AS integer)     AS gold_badges,
    CAST(NULL AS integer)     AS silver_badges,
    CAST(NULL AS integer)     AS bronze_badges,
    CAST(NULL AS text)        AS top_question_title,
    CAST(NULL AS text)        AS top_question_tags,
    CAST(NULL AS integer)     AS top_q_up_votes,
    CAST(NULL AS integer)     AS top_q_down_votes,
    CAST(NULL AS bigint)      AS posts_above_average,
    'EmptySet'                AS rep_category
WHERE NOT EXISTS (
      SELECT 1 
      FROM user_stats us
      LEFT JOIN badge_counts bc ON bc.userid = us.user_id
      LEFT JOIN top_question tq ON tq.owneruserid = us.user_id
      WHERE (us.reputation > 1000 OR COALESCE(bc.gold_badges, 0) > 0)
         OR (COALESCE(tq.up_votes, 0) > 10 AND COALESCE(tq.down_votes, 0) < 5)
);