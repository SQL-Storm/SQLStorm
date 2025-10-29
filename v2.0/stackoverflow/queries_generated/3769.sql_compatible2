WITH
user_stats AS (
    SELECT
        u.id                                 AS user_id,
        u.displayname,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        SUM(COALESCE(p.score, 0))               AS total_score,
        MAX(p.creationdate)                    AS last_post_dt
    FROM users u
    LEFT JOIN posts p
        ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname
),
post_tags AS (
    SELECT
        p.id                                 AS post_id,
        p.owneruserid                        AS owner_user_id,
        TRIM(t)                              AS tag
    FROM posts p,
         LATERAL (
             SELECT unnest(string_to_array(substring(p.tags FROM 2 FOR length(p.tags) - 2), '><')) AS t
         ) lt
    WHERE p.posttypeid = 1
),
tag_pop AS (
    SELECT
        pt.tag,
        COUNT(DISTINCT pt.post_id)            AS posts_tagged,
        COUNT(DISTINCT pt.owner_user_id)      AS distinct_authors,
        AVG(COALESCE(p.score, 0))              AS avg_score,
        SUM(CASE WHEN p.posttypeid = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.posttypeid = 2 THEN 1 ELSE 0 END) AS answer_cnt
    FROM post_tags pt
    LEFT JOIN posts p
        ON p.id = pt.post_id
    GROUP BY pt.tag
),
badge_stats AS (
    SELECT
        b.userid,
        COUNT(*) FILTER (WHERE b.class = 1)   AS gold_cnt,
        COUNT(*) FILTER (WHERE b.class = 2)   AS silver_cnt,
        COUNT(*) FILTER (WHERE b.class = 3)   AS bronze_cnt
    FROM badges b
    GROUP BY b.userid
),
vote_stats AS (
    SELECT
        p.owneruserid                         AS user_id,
        COUNT(v.id) FILTER (WHERE vt.id = 2)  AS up_votes,
        COUNT(v.id) FILTER (WHERE vt.id = 3)  AS down_votes,
        COUNT(v.id) FILTER (WHERE vt.id = 2) - COUNT(v.id) FILTER (WHERE vt.id = 3)  AS net_votes
    FROM posts p
    JOIN votes v
        ON v.postid = p.id
    JOIN votetypes vt
        ON vt.id = v.votetypeid
    GROUP BY p.owneruserid
),
ranked_users AS (
    SELECT
        us.*,
        RANK() OVER (ORDER BY us.total_score DESC) AS score_rank
    FROM user_stats us
    WHERE (us.question_cnt + us.answer_cnt) >= 5
),
user_top_tags AS (
    SELECT
        ru.user_id,
        pt.tag,
        COUNT(*) AS tag_use_cnt,
        ROW_NUMBER() OVER (PARTITION BY ru.user_id ORDER BY COUNT(*) DESC) AS rn
    FROM ranked_users ru
    JOIN post_tags pt
        ON pt.owner_user_id = ru.user_id
    GROUP BY ru.user_id, pt.tag
    HAVING COUNT(*) >= 2
)
SELECT
    ru.score_rank,
    ru.user_id,
    ru.displayname,
    ru.total_score,
    ru.question_cnt,
    ru.answer_cnt,
    COALESCE(bs.gold_cnt, 0)      AS gold_badges,
    COALESCE(vs.net_votes, 0)    AS net_votes,
    STRING_AGG(DISTINCT ut.tag, ', ') FILTER (WHERE ut.rn = 1) AS top_tags,
    CASE
        WHEN ru.last_post_dt IS NULL THEN 'Never posted'
        WHEN ru.last_post_dt < (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 'Stale'
        ELSE 'Active'
    END AS activity_status
FROM ranked_users ru
LEFT JOIN badge_stats bs
    ON bs.userid = ru.user_id
LEFT JOIN vote_stats vs
    ON vs.user_id = ru.user_id
LEFT JOIN user_top_tags ut
    ON ut.user_id = ru.user_id
GROUP BY
    ru.score_rank,
    ru.user_id,
    ru.displayname,
    ru.total_score,
    ru.question_cnt,
    ru.answer_cnt,
    bs.gold_cnt,
    vs.net_votes,
    ru.last_post_dt

UNION ALL

SELECT
    CAST(NULL AS INTEGER) AS score_rank,
    CAST(NULL AS INTEGER) AS user_id,
    'Tag Summary' AS displayname,
    CAST(NULL AS BIGINT) AS total_score,
    CAST(NULL AS INTEGER) AS question_cnt,
    CAST(NULL AS INTEGER) AS answer_cnt,
    CAST(NULL AS INTEGER) AS gold_badges,
    CAST(NULL AS INTEGER) AS net_votes,
    STRING_AGG(tp.tag || ':' || tp.posts_tagged, '; ') AS top_tags,
    CAST(NULL AS TEXT) AS activity_status
FROM tag_pop tp
WHERE tp.avg_score > 0
ORDER BY score_rank NULLS LAST, total_score DESC NULLS LAST;