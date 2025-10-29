WITH 
user_stats AS (
    SELECT 
        u.id                                      AS user_id,
        u.displayname                             AS display_name,
        u.reputation                              AS reputation,
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges,
        (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS question_cnt,
        (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS answer_cnt,
        (SELECT AVG(p.score) FROM posts p WHERE p.owneruserid = u.id AND p.score IS NOT NULL) AS avg_score,
        (SELECT MAX(p.creationdate) 
            FROM posts p 
            WHERE p.owneruserid = u.id 
              AND p.posttypeid IN (1,2))                                   AS last_activity
    FROM users u
    WHERE u.reputation > 5000
),

tag_info AS (
    SELECT 
        t.tagname,
        t.count,
        COALESCE(e.title, '') AS excerpt_title,
        COALESCE(w.title, '') AS wiki_title,
        LOWER(t.tagname) || ':' || REPLACE(COALESCE(e.title,''), ' ', '_') 
            || ':' || REPLACE(COALESCE(w.title,''), ' ', '_')               AS tag_keyword
    FROM tags t
    LEFT JOIN posts e ON e.id = t.excerptpostid
    LEFT JOIN posts w ON w.id = t.wikipostid
    WHERE t.ismoderatoronly = FALSE
),

ranked_questions AS (
    SELECT 
        p.id                     AS post_id,
        p.owneruserid            AS owner_id,
        p.title,
        p.score,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid 
                           ORDER BY p.score DESC, p.creationdate DESC) AS rn
    FROM posts p
    WHERE p.posttypeid = 1
      AND p.score IS NOT NULL
),

top_questions AS (
    SELECT 
        rq.owner_id,
        rq.post_id,
        rq.title,
        rq.score
    FROM ranked_questions rq
    WHERE rq.rn = 1
),

recent_votes AS (
    SELECT 
        v.postid,
        SUM(CASE WHEN vt.id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.id = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(v.creationdate)                         AS last_vote
    FROM votes v
    JOIN votetypes vt ON vt.id = v.votetypeid
    WHERE v.creationdate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY v.postid
),

no_bronze AS (
    SELECT u.id AS user_id
    FROM users u
    WHERE NOT EXISTS (
        SELECT 1 FROM badges b 
        WHERE b.userid = u.id AND b.class = 3
    )
),

combined AS (
    SELECT 
        us.user_id,
        us.display_name,
        us.reputation,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.question_cnt,
        us.answer_cnt,
        ROUND(CAST(us.avg_score AS numeric),2)                AS avg_score,
        COALESCE(us.last_activity, TIMESTAMP '1970-01-01') AS last_activity,
        tq.post_id                                    AS top_q_id,
        tq.title                                      AS top_q_title,
        tq.score                                      AS top_q_score,
        rv.up_votes,
        rv.down_votes,
        rv.last_vote,
        COALESCE(us.display_name,'[deleted]') || ' (rep:'||us.reputation||')' AS display_with_rep,
        CASE WHEN nb.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_no_bronze
    FROM user_stats us
    LEFT JOIN top_questions tq   ON tq.owner_id = us.user_id
    LEFT JOIN recent_votes rv    ON rv.postid = tq.post_id
    LEFT JOIN no_bronze nb       ON nb.user_id = us.user_id
)

SELECT 
    user_id,
    display_name,
    reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    question_cnt,
    answer_cnt,
    avg_score,
    last_activity,
    top_q_id,
    top_q_title,
    top_q_score,
    up_votes,
    down_votes,
    last_vote,
    display_with_rep,
    has_no_bronze
FROM combined
WHERE (up_votes IS NULL OR up_votes > 0)
   AND has_no_bronze = 0
GROUP BY
    user_id,
    display_name,
    reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    question_cnt,
    answer_cnt,
    avg_score,
    last_activity,
    top_q_id,
    top_q_title,
    top_q_score,
    up_votes,
    down_votes,
    last_vote,
    display_with_rep,
    has_no_bronze
ORDER BY reputation DESC, avg_score DESC
LIMIT 100;