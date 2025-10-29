WITH recent_posts AS (
    SELECT 
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn
    FROM posts p
    WHERE p.creationdate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
user_stats AS (
    SELECT 
        u.id                         AS userid,
        u.displayname,
        u.reputation,
        COUNT(*) FILTER (WHERE p.posttypeid = 1)                         AS question_count,
        COUNT(*) FILTER (WHERE p.posttypeid = 2)                         AS answer_count,
        COALESCE(SUM(p.score),0)                                         AS total_score,
        AVG(p.score) FILTER (WHERE p.posttypeid = 2)                     AS avg_answer_score,
        MAX(CASE WHEN p.posttypeid = 1 AND p.acceptedanswerid IS NOT NULL THEN 1 ELSE 0 END) AS has_accepted_answer_flag
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),
badge_agg AS (
    SELECT 
        b.userid,
        STRING_AGG(CASE WHEN b.class = 1 THEN 'Gold:'||b.name END, ',')   AS gold_badges,
        STRING_AGG(CASE WHEN b.class = 2 THEN 'Silver:'||b.name END, ',') AS silver_badges,
        COUNT(*) FILTER (WHERE b.class = 3)                               AS bronze_count
    FROM badges b
    GROUP BY b.userid
)
SELECT 
    us.userid,
    us.displayname,
    us.reputation,
    us.question_count,
    us.answer_count,
    us.total_score,
    ROUND(us.avg_answer_score, 2)                              AS avg_answer_score,
    CASE WHEN us.has_accepted_answer_flag = 1 THEN 'Yes' ELSE 'No' END AS has_accepted_answer,
    COALESCE(ba.gold_badges, '')                               AS gold_badges,
    COALESCE(ba.silver_badges, '')                             AS silver_badges,
    ba.bronze_count,
    (SELECT v.creationdate
     FROM votes v
     WHERE v.postid = (
           SELECT p2.id
           FROM posts p2
           WHERE p2.owneruserid = us.userid
             AND p2.posttypeid = 2
           ORDER BY p2.creationdate DESC
           LIMIT 1)
       AND v.votetypeid = 2
     ORDER BY v.creationdate DESC
     LIMIT 1)                                                  AS last_upvote_on_latest_answer,
    ROW_NUMBER() OVER (ORDER BY us.reputation DESC)           AS reputation_rank
FROM user_stats us
LEFT JOIN badge_agg ba ON ba.userid = us.userid
WHERE us.reputation > 10000
  AND (us.question_count + us.answer_count) > 0
  AND us.displayname IS NOT NULL

UNION ALL

SELECT 
    CAST(NULL AS BIGINT)       AS userid,
    CAST(NULL AS TEXT)         AS displayname,
    CAST(NULL AS BIGINT)       AS reputation,
    CAST(NULL AS BIGINT)       AS question_count,
    CAST(NULL AS BIGINT)       AS answer_count,
    CAST(NULL AS BIGINT)       AS total_score,
    CAST(NULL AS NUMERIC)      AS avg_answer_score,
    CAST(NULL AS TEXT)         AS has_accepted_answer,
    CAST(NULL AS TEXT)         AS gold_badges,
    CAST(NULL AS TEXT)         AS silver_badges,
    CAST(NULL AS BIGINT)       AS bronze_count,
    CAST(NULL AS TIMESTAMP)    AS last_upvote_on_latest_answer,
    CAST(NULL AS BIGINT)       AS reputation_rank

ORDER BY reputation_rank
LIMIT 100 OFFSET 0;