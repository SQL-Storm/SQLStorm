WITH
    user_posts AS (
        SELECT
            u.id AS user_id,
            u.displayname AS display_name,
            COUNT(p.id) AS post_cnt,
            SUM(COALESCE(p.score, 0)) AS total_score,
            MAX(p.creationdate) AS last_post_dt,
            COUNT(CASE WHEN p.posttypeid = 1 THEN 1 END) AS question_cnt,
            COUNT(CASE WHEN p.posttypeid = 2 THEN 1 END) AS answer_cnt
        FROM users u
        LEFT JOIN posts p
               ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname
    ),
    user_badges AS (
        SELECT
            b.userid AS user_id,
            COUNT(*) AS badge_cnt,
            SUM(CASE b.class
                    WHEN 1 THEN 10
                    WHEN 2 THEN 5
                    ELSE 1
                END) AS badge_weight
        FROM badges b
        GROUP BY b.userid
    ),
    recent_votes AS (
        SELECT
            v.postid,
            MAX(v.creationdate) AS last_vote_dt
        FROM votes v
        GROUP BY v.postid
    ),
    user_tags AS (
        SELECT
            p.owneruserid AS user_id,
            STRING_AGG(DISTINCT t.tagname, ',') AS tags_list
        FROM posts p
        -- split tags like '<tag1><tag2>' into rows using standard SQL functions
        JOIN LATERAL (
            SELECT TRIM(both '<>' FROM value) AS tag
            FROM (
                SELECT unnest(string_to_array(p.tags, '><')) AS value
            ) AS s
        ) AS split ON split.tag <> ''
        JOIN tags t ON t.tagname = split.tag
        WHERE p.owneruserid IS NOT NULL
        GROUP BY p.owneruserid
    )

SELECT
    u.id AS user_id,
    u.displayname AS display_name,
    COALESCE(up.post_cnt, 0) AS post_cnt,
    COALESCE(up.total_score, 0) AS total_score,
    COALESCE(ub.badge_cnt, 0) AS badge_cnt,
    COALESCE(ub.badge_weight, 0) AS badge_weight,
    ROW_NUMBER() OVER (ORDER BY COALESCE(up.total_score, 0) + COALESCE(ub.badge_weight, 0) DESC) AS reputation_rank,
    CASE WHEN COALESCE(ub.badge_cnt, 0) > 5 THEN 'PowerUser' ELSE 'Regular' END AS user_tier,
    (SELECT COUNT(*) FROM posts p
        WHERE p.owneruserid = u.id
          AND p.posttypeid = 1
          AND p.creationdate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')) AS recent_questions,
    (SELECT COUNT(*) FROM posts p
        WHERE p.owneruserid = u.id
          AND p.posttypeid = 2
          AND p.creationdate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')) AS recent_answers,
    (SELECT MAX(COALESCE(p2.score,0)) FROM posts p2 WHERE p2.owneruserid = u.id) AS max_post_score,
    (SELECT MAX(rv.last_vote_dt) FROM recent_votes rv
        JOIN posts p3 ON p3.id = rv.postid
        WHERE p3.owneruserid = u.id) AS last_vote_on_user_posts,
    ut.tags_list AS top_tags_used
FROM users u
LEFT JOIN user_posts up ON up.user_id = u.id
LEFT JOIN user_badges ub ON ub.user_id = u.id
LEFT JOIN user_tags ut ON ut.user_id = u.id
WHERE u.reputation > 1000

UNION ALL

SELECT
    NULL AS user_id,
    'Aggregate' AS display_name,
    SUM(COALESCE(up.post_cnt,0)) AS post_cnt,
    SUM(COALESCE(up.total_score,0)) AS total_score,
    SUM(COALESCE(ub.badge_cnt,0)) AS badge_cnt,
    SUM(COALESCE(ub.badge_weight,0)) AS badge_weight,
    NULL AS reputation_rank,
    NULL AS user_tier,
    NULL AS recent_questions,
    NULL AS recent_answers,
    NULL AS max_post_score,
    NULL AS last_vote_on_user_posts,
    NULL AS top_tags_used
FROM users u
LEFT JOIN user_posts up ON up.user_id = u.id
LEFT JOIN user_badges ub ON ub.user_id = u.id
WHERE u.reputation > 1000;