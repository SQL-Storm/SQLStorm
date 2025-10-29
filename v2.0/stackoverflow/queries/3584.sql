WITH
user_stats AS (
    SELECT
        u.id                                    AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(u.upvotes, 0) - COALESCE(u.downvotes, 0) AS net_votes,
        COUNT(b.id) FILTER (WHERE b.class = 1) AS gold_badges,
        COUNT(b.id) FILTER (WHERE b.class = 2) AS silver_badges,
        COUNT(b.id) FILTER (WHERE b.class = 3) AS bronze_badges,
        COUNT(v.id) FILTER (WHERE v.votetypeid = 2) AS upvote_count,
        COUNT(v.id) FILTER (WHERE v.votetypeid = 3) AS downvote_count
    FROM users u
    LEFT JOIN badges b ON b.userid = u.id
    LEFT JOIN votes  v ON v.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation, u.upvotes, u.downvotes
),
recent_questions AS (
    SELECT
        p.id                                    AS q_id,
        p.title,
        p.creationdate,
        p.score                                 AS q_score,
        p.viewcount,
        p.favoritecount,
        p.tags,
        ROW_NUMBER() OVER (PARTITION BY tag
                           ORDER BY p.score DESC, p.creationdate DESC) AS tag_rank
    FROM posts p,
         regexp_split_to_table(p.tags, '[><]') AS tag
    WHERE p.posttypeid = 1
      AND p.creationdate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
answer_stats AS (
    SELECT
        q.id                                    AS q_id,
        COUNT(a.id)                             AS answer_cnt,
        AVG(a.score)                            AS avg_answer_score,
        MAX(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS has_accepted
    FROM posts q
    LEFT JOIN posts a
        ON a.parentid = q.id AND a.posttypeid = 2
    WHERE q.posttypeid = 1
    GROUP BY q.id
),
tag_popularity AS (
    SELECT
        tag,
        COUNT(*)                AS question_cnt,
        SUM(p.score)            AS total_score,
        AVG(p.viewcount)        AS avg_views
    FROM posts p,
         regexp_split_to_table(p.tags, '[><]') AS tag
    WHERE p.posttypeid = 1
      AND p.tags IS NOT NULL
    GROUP BY tag
    HAVING COUNT(*) > 100
)
SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.net_votes,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    rq.q_id,
    rq.title,
    rq.creationdate,
    rq.q_score,
    rq.viewcount,
    COALESCE(rq.favoritecount, 0)               AS fav_cnt,
    an.answer_cnt,
    ROUND(an.avg_answer_score, 2)               AS avg_ans_score,
    CASE WHEN an.has_accepted = 1 THEN 'YES' ELSE 'NO' END AS has_accepted,
    rq.tags,
    tp.tag                                    AS top_tag,
    tp.question_cnt,
    tp.total_score,
    ROUND(tp.avg_views, 0)                     AS avg_views,
    ROW_NUMBER() OVER (PARTITION BY us.user_id ORDER BY rq.q_score DESC) AS user_q_rank
FROM user_stats us
LEFT JOIN LATERAL (
        SELECT *
        FROM recent_questions rq
        WHERE rq.q_id = (
                SELECT p.id
                FROM posts p
                WHERE p.owneruserid = us.user_id
                  AND p.posttypeid = 1
                ORDER BY p.creationdate DESC
                LIMIT 1
        )
) rq ON TRUE
LEFT JOIN answer_stats an      ON an.q_id = rq.q_id
LEFT JOIN LATERAL (
        SELECT t.tag
        FROM regexp_split_to_table(rq.tags, '[><]') AS t(tag)
        ORDER BY t.tag
        LIMIT 1
) AS first_tag(tag) ON TRUE
LEFT JOIN tag_popularity tp    ON tp.tag = first_tag.tag
WHERE (us.reputation > 20000)
   OR (us.gold_badges > 5 AND rq.q_score > 50)
   OR (tp.question_cnt IS NOT NULL AND tp.avg_views > 5000)
UNION ALL
SELECT
    u.id                                 AS user_id,
    u.displayname,
    u.reputation,
    COALESCE(u.upvotes, 0) - COALESCE(u.downvotes, 0) AS net_votes,
    0                                    AS gold_badges,
    0                                    AS silver_badges,
    0                                    AS bronze_badges,
    NULL                                 AS q_id,
    NULL                                 AS title,
    NULL                                 AS creationdate,
    NULL                                 AS q_score,
    NULL                                 AS viewcount,
    NULL                                 AS fav_cnt,
    NULL                                 AS answer_cnt,
    NULL                                 AS avg_ans_score,
    NULL                                 AS has_accepted,
    NULL                                 AS tags,
    NULL                                 AS top_tag,
    NULL                                 AS question_cnt,
    NULL                                 AS total_score,
    NULL                                 AS avg_views,
    NULL                                 AS user_q_rank
FROM users u
WHERE u.creationdate >= CAST('2024-10-01' AS date) - INTERVAL '7 days'
  AND NOT EXISTS (SELECT 1 FROM posts p WHERE p.owneruserid = u.id);