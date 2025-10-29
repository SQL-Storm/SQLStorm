-- {"query": "3518.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2206}
WITH 
user_activity AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname                         AS display_name,
        u.reputation,
        COUNT(p.id)                            AS total_posts,
        SUM(CASE WHEN p.posttypeid = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.posttypeid = 2 THEN 1 ELSE 0 END) AS answer_cnt,
        COALESCE(SUM(p.score),0)               AS total_score,
        MAX(p.creationdate)                   AS last_post_date
    FROM users u
    LEFT JOIN posts p
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),
user_badges AS (
    SELECT
        b.userid                               AS user_id,
        COUNT(*)                               AS badge_cnt,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        STRING_AGG(DISTINCT b.name, ', ')      AS badge_names
    FROM badges b
    GROUP BY b.userid
),
user_tag_usage AS (
    /* expand tags using a standard SQL approach: split into rows via recursive CTE */
    SELECT
        post_tags.owneruserid AS user_id,
        s.tag,
        COUNT(*) AS tag_use_cnt
    FROM (
        SELECT
            owneruserid,
            TRIM(BOTH '<>' FROM tags) AS tags_clean
        FROM posts
        WHERE posttypeid = 1
          AND tags IS NOT NULL
    ) post_tags
    JOIN LATERAL (
        WITH RECURSIVE split(idx, rest, tag) AS (
            SELECT
                1 AS idx,
                post_tags.tags_clean AS rest,
                CAST(NULL AS text) AS tag
            UNION ALL
            SELECT
                idx + 1,
                CASE
                    WHEN POSITION('><' IN rest) = 0 THEN ''
                    ELSE SUBSTR(rest, POSITION('><' IN rest) + 2)
                END AS rest,
                CASE
                    WHEN POSITION('><' IN rest) = 0 THEN rest
                    ELSE SUBSTR(rest, 1, POSITION('><' IN rest) - 1)
                END AS tag
            FROM split
            WHERE rest <> ''
        )
        SELECT tag FROM split WHERE tag IS NOT NULL
    ) s ON TRUE
    GROUP BY post_tags.owneruserid, s.tag
),
top_tags AS (
    SELECT
        user_id,
        tag,
        tag_use_cnt,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_use_cnt DESC) AS rn
    FROM user_tag_usage
),
low_rep_high_badge AS (
    SELECT
        ua.user_id,
        ua.display_name,
        ua.reputation,
        ua.total_posts,
        ua.question_cnt,
        ua.answer_cnt,
        ua.total_score,
        COALESCE(ub.badge_cnt,0)               AS badge_cnt,
        COALESCE(ub.gold_cnt,0)                AS gold_cnt,
        COALESCE(ub.silver_cnt,0)              AS silver_cnt,
        COALESCE(ub.bronze_cnt,0)              AS bronze_cnt,
        ub.badge_names,
        0                                      AS closed_q_cnt,
        0                                      AS up_votes_cast,
        0                                      AS down_votes_cast,
        NULL                                   AS top3_tags,
        ROW_NUMBER() OVER (ORDER BY COALESCE(ub.badge_cnt,0) DESC) AS rank_by_badges
    FROM user_activity ua
    LEFT JOIN user_badges ub
           ON ub.user_id = ua.user_id
    WHERE ua.reputation < 2000
      AND COALESCE(ub.badge_cnt,0) >= 10
)
SELECT
    ua.user_id,
    ua.display_name,
    ua.reputation,
    ua.total_posts,
    ua.question_cnt,
    ua.answer_cnt,
    ua.total_score,
    COALESCE(ub.badge_cnt,0)               AS badge_cnt,
    COALESCE(ub.gold_cnt,0)                AS gold_cnt,
    COALESCE(ub.silver_cnt,0)              AS silver_cnt,
    COALESCE(ub.bronze_cnt,0)              AS bronze_cnt,
    ub.badge_names,
    (SELECT COUNT(*)
       FROM posts p2
      WHERE p2.owneruserid = ua.user_id
        AND p2.posttypeid = 1
        AND p2.closeddate IS NOT NULL)   AS closed_q_cnt,
    (SELECT COUNT(*) FROM votes v WHERE v.userid = ua.user_id AND v.votetypeid = 2) AS up_votes_cast,
    (SELECT COUNT(*) FROM votes v WHERE v.userid = ua.user_id AND v.votetypeid = 3) AS down_votes_cast,
    (SELECT STRING_AGG(t.tag, ', ')
       FROM top_tags t
      WHERE t.user_id = ua.user_id
        AND t.rn <= 3)                    AS top3_tags,
    ROW_NUMBER() OVER (ORDER BY ua.reputation DESC) AS rank_by_reputation
FROM user_activity ua
LEFT JOIN user_badges ub
       ON ub.user_id = ua.user_id
WHERE ua.reputation >= 10000
  AND (ua.total_posts >= 100 OR COALESCE(ub.badge_cnt,0) >= 5)

UNION ALL

SELECT
    lr.user_id,
    lr.display_name,
    lr.reputation,
    lr.total_posts,
    lr.question_cnt,
    lr.answer_cnt,
    lr.total_score,
    lr.badge_cnt,
    lr.gold_cnt,
    lr.silver_cnt,
    lr.bronze_cnt,
    lr.badge_names,
    lr.closed_q_cnt,
    lr.up_votes_cast,
    lr.down_votes_cast,
    lr.top3_tags,
    lr.rank_by_badges
FROM low_rep_high_badge lr
ORDER BY reputation DESC NULLS LAST, badge_cnt DESC
LIMIT 100;