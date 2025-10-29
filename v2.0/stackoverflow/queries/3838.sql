-- {"query": "3838.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1978}
WITH
    user_stats AS (
        SELECT
            u.id,
            u.displayname,
            u.reputation,
            COALESCE(u.upvotes, 0) - COALESCE(u.downvotes, 0) AS net_votes,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges
        FROM users u
    ),
    latest_question AS (
        SELECT
            p.id,
            p.owneruserid,
            p.title,
            p.score,
            p.creationdate,
            p.tags,
            ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn
        FROM posts p
        WHERE p.posttypeid = 1
    ),
    post_votes AS (
        SELECT
            v.postid,
            SUM(CASE WHEN vt.id = 2 THEN 1 WHEN vt.id = 3 THEN -1 ELSE 0 END) AS vote_score
        FROM votes v
        JOIN votetypes vt ON vt.id = v.votetypeid
        GROUP BY v.postid
    ),
    user_activity AS (
        SELECT
            us.id,
            us.displayname,
            us.reputation,
            us.net_votes,
            us.gold_badges,
            us.silver_badges,
            us.bronze_badges,
            lq.title,
            lq.score AS question_score,
            lq.creationdate,
            COALESCE(pv.vote_score, 0) AS question_vote_score,
            CASE
                WHEN lq.tags IS NULL THEN ''
                ELSE REPLACE(SUBSTRING(lq.tags FROM 2 FOR CHAR_LENGTH(lq.tags) - 2), '><', ', ')
            END AS tag_list
        FROM user_stats us
        LEFT JOIN latest_question lq
               ON lq.owneruserid = us.id AND lq.rn = 1
        LEFT JOIN post_votes pv
               ON pv.postid = lq.id
    ),
    ranked_users AS (
        SELECT
            ua.id,
            ua.displayname,
            ua.reputation,
            ua.net_votes,
            ua.gold_badges,
            ua.silver_badges,
            ua.bronze_badges,
            ua.title,
            ua.question_score,
            ua.creationdate,
            ua.question_vote_score,
            ua.tag_list,
            ROW_NUMBER() OVER (ORDER BY ua.reputation DESC, ua.net_votes DESC, ua.question_vote_score DESC) AS rank
        FROM user_activity ua
        WHERE ua.reputation > 1000
    ),
    top_tags AS (
        SELECT
            t.tagname,
            t.count,
            ROW_NUMBER() OVER (ORDER BY t.count DESC) AS rn
        FROM tags t
        WHERE t.ismoderatoronly = FALSE
    ),
    unused_tags AS (
        SELECT
            t.tagname,
            t.count
        FROM tags t
        LEFT JOIN posts p
               ON p.tags LIKE '%' || t.tagname || '%'
               AND p.posttypeid = 1
        WHERE p.id IS NULL
    )

SELECT
    ru.id,
    ru.displayname,
    ru.reputation,
    ru.net_votes,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.title,
    ru.question_score,
    ru.question_vote_score,
    ru.creationdate,
    ru.tag_list,
    tt.tagname AS related_tag,
    tt.count AS related_tag_usage,
    CAST(NULL AS TEXT) AS unused_tag_name,
    CAST(NULL AS BIGINT) AS unused_tag_count,
    ru.rank
FROM ranked_users ru
LEFT JOIN top_tags tt
       ON tt.rn = 1
WHERE ru.rank <= 100

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS id,
    CAST(NULL AS TEXT) AS displayname,
    CAST(NULL AS BIGINT) AS reputation,
    CAST(NULL AS BIGINT) AS net_votes,
    CAST(NULL AS BIGINT) AS gold_badges,
    CAST(NULL AS BIGINT) AS silver_badges,
    CAST(NULL AS BIGINT) AS bronze_badges,
    CAST(NULL AS TEXT) AS title,
    CAST(NULL AS BIGINT) AS question_score,
    CAST(NULL AS BIGINT) AS question_vote_score,
    CAST(NULL AS TIMESTAMP) AS creationdate,
    CAST(NULL AS TEXT) AS tag_list,
    CAST(NULL AS TEXT) AS related_tag,
    CAST(NULL AS BIGINT) AS related_tag_usage,
    ut.tagname AS unused_tag_name,
    ut.count AS unused_tag_count,
    CAST(NULL AS BIGINT) AS rank
FROM unused_tags ut
ORDER BY rank NULLS LAST, unused_tag_count DESC
FETCH FIRST 100 ROWS ONLY;