WITH
user_stats AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(u.location, 'Unknown')        AS location,
        COALESCE(u.websiteurl, '')             AS website,
        (SELECT COUNT(*) FROM posts p
         WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS question_cnt,
        (SELECT COUNT(*) FROM posts p
         WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS answer_cnt,
        (SELECT COUNT(*) FROM badges b
         WHERE b.userid = u.id)               AS badge_cnt,
        (SELECT COALESCE(SUM(v.bountyamount),0)
         FROM votes v
         WHERE v.userid = u.id AND v.votetypeid = 8)       AS bounty_started,
        ROW_NUMBER() OVER (ORDER BY u.reputation DESC) AS rep_rank
    FROM users u
    WHERE u.reputation > 1000
),

tag_activity AS (
    SELECT
        t.tagname,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS q_posts,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS a_posts,
        SUM(p.score)                               AS total_score,
        MAX(p.creationdate)                        AS latest_post
    FROM tags t
    LEFT JOIN posts p
           ON p.tags IS NOT NULL
          AND POSITION('<' || t.tagname || '>' IN p.tags) > 0
    GROUP BY t.tagname
    HAVING COUNT(p.id) > 10
),

top_posts AS (
    SELECT
        p.id,
        p.title,
        p.score,
        p.viewcount,
        COALESCE(p.favoritecount,0) + COALESCE(p.answercount,0) AS engagement,
        ROW_NUMBER() OVER (
            PARTITION BY p.posttypeid
            ORDER BY (p.score * LOG(1 + p.viewcount)) DESC
        ) AS rn
    FROM posts p
    WHERE p.posttypeid IN (1,2)
),

recent_closed AS (
    SELECT
        ph.postid,
        MIN(ph.creationdate)                     AS closed_date,
        STRING_AGG(DISTINCT crt.name, ', ')      AS close_reasons
    FROM posthistory ph
    JOIN closereasontypes crt
          ON crt.id = CAST(ph.comment AS SMALLINT)
    WHERE ph.posthistorytypeid = 10
    GROUP BY ph.postid
),

combined AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.rep_rank,
        us.question_cnt,
        us.answer_cnt,
        us.badge_cnt,
        us.bounty_started,
        rc.closed_date,
        rc.close_reasons
    FROM user_stats us
    LEFT JOIN recent_closed rc
           ON rc.postid = (
               SELECT p.id
               FROM posts p
               WHERE p.owneruserid = us.user_id
                 AND p.creationdate < CAST('2024-10-01 12:34:56' AS TIMESTAMP)
               ORDER BY p.creationdate DESC
               LIMIT 1
           )
)

SELECT *
FROM combined
WHERE rep_rank <= 100

UNION ALL

SELECT
    NULL                                           AS user_id,
    'Tag Summary'                                  AS displayname,
    NULL                                           AS reputation,
    NULL                                           AS rep_rank,
    ta.q_posts                                     AS question_cnt,
    ta.a_posts                                     AS answer_cnt,
    NULL                                           AS badge_cnt,
    NULL                                           AS bounty_started,
    ta.latest_post                                 AS closed_date,
    CAST(ta.total_score AS VARCHAR)                AS close_reasons
FROM tag_activity ta
ORDER BY
    reputation DESC NULLS LAST,
    question_cnt DESC
LIMIT 200;