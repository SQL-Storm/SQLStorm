-- {"query": "3878.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2050} 

WITH
    -- Aggregate post statistics per user (including users without posts)
    user_posts AS (
        SELECT
            u.id                                 AS user_id,
            u.displayname                        AS display_name,
            COUNT(p.id)                          AS post_cnt,
            SUM(COALESCE(p.score, 0))            AS total_score,
            MAX(p.creationdate)                  AS last_post_dt,
            COUNT(CASE WHEN p.posttypeid = 1 THEN 1 END) AS question_cnt,
            COUNT(CASE WHEN p.posttypeid = 2 THEN 1 END) AS answer_cnt
        FROM users u
        LEFT JOIN posts p
               ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname
    ),

    -- Badge aggregates per user, with a weighted score for badge class
    user_badges AS (
        SELECT
            b.userid                                 AS user_id,
            COUNT(*)                                 AS badge_cnt,
            SUM(CASE b.class
                    WHEN 1 THEN 10   -- gold
                    WHEN 2 THEN 5    -- silver
                    ELSE 1           -- bronze
                END)                                 AS badge_weight
        FROM badges b
        GROUP BY b.userid
    ),

    -- Latest vote date per post (correlated sub‑query later will join this)
    recent_votes AS (
        SELECT
            v.postid,
            MAX(v.creationdate) AS last_vote_dt
        FROM votes v
        GROUP BY v.postid
    ),

    -- Tags used by a user (string aggregation of distinct tag names)
    user_tags AS (
        SELECT
            p.owneruserid                         AS user_id,
            STRING_AGG(DISTINCT t.tagname, ',')   AS tags_list
        FROM posts p
        JOIN LATERAL regexp_split_to_table(p.tags, '[><]') AS split(tag) ON true
        JOIN tags t ON t.tagname = split.tag
        WHERE p.owneruserid IS NOT NULL
        GROUP BY p.owneruserid
    )

SELECT
    u.id                                   AS user_id,
    u.displayname                          AS display_name,
    COALESCE(up.post_cnt, 0)                AS post_cnt,
    COALESCE(up.total_score, 0)             AS total_score,
    COALESCE(ub.badge_cnt, 0)               AS badge_cnt,
    COALESCE(ub.badge_weight, 0)           AS badge_weight,
    ROW_NUMBER() OVER (ORDER BY
        COALESCE(up.total_score, 0) + COALESCE(ub.badge_weight, 0) DESC
    )                                      AS reputation_rank,
    CASE
        WHEN COALESCE(ub.badge_cnt, 0) > 5 THEN 'PowerUser'
        ELSE 'Regular'
    END                                    AS user_tier,
    -- Recent activity in the last 30 days
    (SELECT COUNT(*) FROM posts p
        WHERE p.owneruserid = u.id
          AND p.posttypeid = 1               -- questions
          AND p.creationdate > now() - INTERVAL '30 days') AS recent_questions,
    (SELECT COUNT(*) FROM posts p
        WHERE p.owneruserid = u.id
          AND p.posttypeid = 2               -- answers
          AND p.creationdate > now() - INTERVAL '30 days') AS recent_answers,
    -- Highest scoring post of the user
    (SELECT MAX(COALESCE(p2.score,0)) FROM posts p2
        WHERE p2.owneruserid = u.id)       AS max_post_score,
    -- Date of the most recent vote on any of the user's posts
    (SELECT MAX(rv.last_vote_dt) FROM recent_votes rv
        JOIN posts p3 ON p3.id = rv.postid
        WHERE p3.owneruserid = u.id)        AS last_vote_on_user_posts,
    ut.tags_list                            AS top_tags_used
FROM users u
LEFT JOIN user_posts   up ON up.user_id = u.id
LEFT JOIN user_badges  ub ON ub.user_id = u.id
LEFT JOIN user_tags    ut ON ut.user_id = u.id
WHERE u.reputation > 1000

UNION ALL

-- Aggregate row summarizing all selected users
SELECT
    NULL                                   AS user_id,
    'Aggregate'                            AS display_name,
    SUM(COALESCE(up.post_cnt,0))            AS post_cnt,
    SUM(COALESCE(up.total_score,0))         AS total_score,
    SUM(COALESCE(ub.badge_cnt,0))           AS badge_cnt,
    SUM(COALESCE(ub.badge_weight,0))       AS badge_weight,
    NULL                                   AS reputation_rank,
    NULL                                   AS user_tier,
    NULL                                   AS recent_questions,
    NULL                                   AS recent_answers,
    NULL                                   AS max_post_score,
    NULL                                   AS last_vote_on_user_posts,
    NULL                                   AS top_tags_used
FROM users u
LEFT JOIN user_posts  up ON up.user_id = u.id
LEFT JOIN user_badges ub ON ub.user_id = u.id
WHERE u.reputation > 1000;
