WITH
user_stats AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname,
        u.reputation,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        SUM(COALESCE(p.score, 0))               AS total_score,
        MAX(p.creationdate)                    AS last_post_dt,
        MAX(v.creationdate) FILTER (WHERE v.votetypeid = 2) AS last_upvote_dt
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    LEFT JOIN votes v ON v.postid = p.id
    GROUP BY u.id, u.displayname, u.reputation
),
badge_agg AS (
    SELECT
        b.userid,
        COUNT(*)                                    AS badge_total,
        COUNT(*) FILTER (WHERE b.class = 1)         AS gold_badge_cnt,
        STRING_AGG(DISTINCT b.name, ', ')           AS badge_list
    FROM badges b
    GROUP BY b.userid
),
top_tags AS (
    SELECT
        t.tagname,
        t.count                AS tag_use_cnt,
        COALESCE(e.title, '')  AS excerpt_title,
        COALESCE(w.title, '')  AS wiki_title
    FROM tags t
    LEFT JOIN posts e ON e.id = t.excerptpostid
    LEFT JOIN posts w ON w.id = t.wikipostid
    WHERE t.count > 5000
    ORDER BY t.count DESC
    LIMIT 10
)
SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.question_cnt,
    us.answer_cnt,
    us.total_score,
    COALESCE(ba.badge_total, 0)        AS badge_total,
    COALESCE(ba.gold_badge_cnt, 0)     AS gold_badge_cnt,
    ba.badge_list,
    us.last_post_dt,
    us.last_upvote_dt,
    CASE
        WHEN us.reputation > 20000 THEN 'Elite'
        WHEN us.reputation BETWEEN 10000 AND 19999 THEN 'Pro'
        ELSE 'Regular'
    END                                 AS reputation_tier,
    ROW_NUMBER() OVER (ORDER BY us.reputation DESC NULLS LAST, us.total_score DESC NULLS LAST) AS rep_rank,
    (SELECT COUNT(*)
       FROM posts p30
      WHERE p30.owneruserid = us.user_id
        AND p30.creationdate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)) AS posts_last_30d,
    (SELECT COUNT(*)
       FROM comments c30
      WHERE c30.userid = us.user_id
        AND c30.creationdate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)) AS comments_last_30d,
    (SELECT STRING_AGG(DISTINCT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM tag)), '; ')
       FROM (
            SELECT regexp_split_to_table(p.tags, '><') AS tag
              FROM posts p
             WHERE p.owneruserid = us.user_id
               AND p.posttypeid = 1
               AND p.tags IS NOT NULL
            ) AS tags_sub)                         AS question_tags_used
FROM user_stats us
LEFT JOIN badge_agg ba ON ba.userid = us.user_id
WHERE us.reputation IS NOT NULL
  AND (us.question_cnt + us.answer_cnt) > 0

UNION ALL

SELECT
    -1                                     AS user_id,
    'Summary'                              AS displayname,
    NULL                                   AS reputation,
    SUM(us.question_cnt)                   AS question_cnt,
    SUM(us.answer_cnt)                     AS answer_cnt,
    SUM(us.total_score)                    AS total_score,
    NULL                                   AS badge_total,
    NULL                                   AS gold_badge_cnt,
    NULL                                   AS badge_list,
    MAX(us.last_post_dt)                   AS last_post_dt,
    MAX(us.last_upvote_dt)                 AS last_upvote_dt,
    NULL                                   AS reputation_tier,
    NULL                                   AS rep_rank,
    NULL                                   AS posts_last_30d,
    NULL                                   AS comments_last_30d,
    NULL                                   AS question_tags_used
FROM user_stats us
WHERE us.reputation > 1000
  AND NOT EXISTS (
        SELECT 1
          FROM badges b
         WHERE b.userid = us.user_id
           AND b.class = 1
      );