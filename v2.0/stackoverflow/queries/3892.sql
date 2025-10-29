-- {"query": "3892.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2155}
WITH
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(p.cnt,0)                        AS total_posts,
        COALESCE(a.cnt,0)                        AS total_answers,
        COALESCE(q.score_sum,0)                  AS question_score_sum,
        COALESCE(b.cnt,0)                        AS badge_cnt,
        COALESCE(v.up_votes,0)                   AS up_vote_cnt,
        ROW_NUMBER() OVER (ORDER BY COALESCE(v.up_votes,0) DESC, u.reputation DESC) AS rank_up_votes
    FROM users u
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS cnt
        FROM posts
        WHERE owneruserid IS NOT NULL
        GROUP BY owneruserid
    ) p  ON u.id = p.owneruserid
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS cnt
        FROM posts
        WHERE posttypeid = 2
        GROUP BY owneruserid
    ) a  ON u.id = a.owneruserid
    LEFT JOIN (
        SELECT owneruserid, SUM(score) AS score_sum
        FROM posts
        WHERE posttypeid = 1
        GROUP BY owneruserid
    ) q  ON u.id = q.owneruserid
    LEFT JOIN (
        SELECT userid, COUNT(*) AS cnt
        FROM badges
        GROUP BY userid
    ) b  ON u.id = b.userid
    LEFT JOIN (
        SELECT p.owneruserid,
               SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes
        FROM posts p
        LEFT JOIN votes v ON p.id = v.postid
        GROUP BY p.owneruserid
    ) v  ON u.id = v.owneruserid
),

latest_post AS (
    SELECT
        p.owneruserid,
        p.id                AS post_id,
        p.creationdate,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
),

tag_metrics AS (
    SELECT
        t.tagname,
        COUNT(DISTINCT pl.postid)                                   AS linked_posts,
        COUNT(DISTINCT CASE WHEN pl.linktypeid = 3 THEN pl.postid END) AS duplicate_posts,
        STRING_AGG(DISTINCT u.displayname, ', ') FILTER (WHERE u.displayname IS NOT NULL) AS top_question_authors
    FROM tags t
    LEFT JOIN postlinks pl ON t.id = pl.postid OR t.id = pl.relatedpostid
    LEFT JOIN posts p ON pl.postid = p.id
    LEFT JOIN users u ON p.owneruserid = u.id AND p.posttypeid = 1
    GROUP BY t.tagname
),

main_select AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.total_posts,
        us.total_answers,
        us.question_score_sum,
        us.badge_cnt,
        us.up_vote_cnt,
        us.rank_up_votes,
        lp.post_id               AS latest_post_id,
        lp.creationdate          AS latest_post_date,
        tm.tagname,
        tm.linked_posts,
        tm.duplicate_posts,
        tm.top_question_authors
    FROM user_stats us
    LEFT JOIN (
        SELECT owneruserid, post_id, creationdate
        FROM latest_post
        WHERE rn = 1
    ) lp ON us.user_id = lp.owneruserid
    LEFT JOIN (
        SELECT tagname, linked_posts, duplicate_posts, top_question_authors
        FROM tag_metrics
        WHERE linked_posts > 1000
    ) tm ON (CASE WHEN tm.tagname ~ '^[0-9]+$' THEN CAST(tm.tagname AS INTEGER) ELSE NULL END) = us.user_id
    WHERE
        (us.reputation > 10000 OR us.badge_cnt >= 5)
        AND us.up_vote_cnt > 0
        AND us.displayname IS NOT NULL
    ORDER BY us.rank_up_votes
    LIMIT 100
),

overall_stats AS (
    SELECT
        NULL::INTEGER                AS user_id,
        'Overall Statistics'         AS displayname,
        NULL::INTEGER                AS reputation,
        SUM(us.total_posts)          AS total_posts,
        SUM(us.total_answers)        AS total_answers,
        SUM(us.question_score_sum)   AS question_score_sum,
        SUM(us.badge_cnt)            AS badge_cnt,
        SUM(us.up_vote_cnt)          AS up_vote_cnt,
        NULL::INTEGER                AS rank_up_votes,
        NULL::INTEGER                AS latest_post_id,
        NULL::TIMESTAMP              AS latest_post_date,
        NULL::TEXT                   AS tagname,
        NULL::BIGINT                 AS linked_posts,
        NULL::BIGINT                 AS duplicate_posts,
        NULL::TEXT                   AS top_question_authors
    FROM user_stats us
    WHERE us.reputation > 0
)

SELECT * FROM main_select
UNION ALL
SELECT * FROM overall_stats;