-- {"query": "3798.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2589} 

WITH
    /* Aggregate badge counts per user */
    UserBadgeCounts AS (
        SELECT u.id                                      AS userid,
               COUNT(*) FILTER (WHERE b.class = 1)      AS gold_badges,
               COUNT(*) FILTER (WHERE b.class = 2)      AS silver_badges,
               COUNT(*) FILTER (WHERE b.class = 3)      AS bronze_badges,
               COUNT(*)                                 AS total_badges
        FROM   users u
        LEFT JOIN badges b ON b.userid = u.id
        GROUP BY u.id
    ),
    /* Aggregate post statistics per user */
    UserPostStats AS (
        SELECT u.id                                               AS userid,
               COUNT(p.id) FILTER (WHERE p.posttypeid = 1)       AS question_cnt,
               COUNT(p.id) FILTER (WHERE p.posttypeid = 2)       AS answer_cnt,
               COALESCE(SUM(p.score),0)                          AS total_score,
               MAX(p.creationdate)                               AS latest_post_date,
               (SELECT p2.id
                  FROM posts p2
                 WHERE p2.owneruserid = u.id
                 ORDER BY p2.creationdate DESC
                 LIMIT 1)                                         AS latest_post_id
        FROM   users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id
    ),
    /* Aggregate comment statistics per user */
    UserCommentStats AS (
        SELECT u.id                                     AS userid,
               COUNT(c.id)                              AS comment_cnt,
               MAX(c.creationdate)                      AS latest_comment_date
        FROM   users u
        LEFT JOIN comments c ON c.userid = u.id
        GROUP BY u.id
    ),
    /* Aggregate vote statistics per user */
    UserVoteStats AS (
        SELECT u.id                                                       AS userid,
               COUNT(v.id) FILTER (WHERE vt.name = 'UpMod')               AS upvotes_given,
               COUNT(v.id) FILTER (WHERE vt.name = 'DownMod')             AS downvotes_given,
               COUNT(v.id) FILTER (WHERE vt.name = 'Favorite')            AS favorites_given
        FROM   users u
        LEFT JOIN votes v   ON v.userid = u.id
        LEFT JOIN votetypes vt ON vt.id = v.votetypeid
        GROUP BY u.id
    ),
    /* Rank users by score and by location */
    RankedUsers AS (
        SELECT u.id,
               u.displayname,
               COALESCE(up.total_score,0)                         AS total_score,
               ROW_NUMBER() OVER (ORDER BY COALESCE(up.total_score,0) DESC,
                                            u.reputation DESC)    AS score_rank,
               ROW_NUMBER() OVER (PARTITION BY u.location
                                  ORDER BY COALESCE(up.total_score,0) DESC) AS loc_rank,
               CASE WHEN u.emailhash IS NULL THEN 'NO_EMAIL' ELSE 'HAS_EMAIL' END AS email_flag,
               u.location
        FROM   users u
        LEFT JOIN UserPostStats up ON up.userid = u.id
    )
SELECT
    ru.id                                           AS user_id,
    ru.displayname                                 AS display_name,
    ub.total_badges,
    ru.total_score,
    ru.score_rank,
    ru.loc_rank,
    ru.email_flag,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ups.question_cnt,
    ups.answer_cnt,
    ups.latest_post_date,
    ucs.comment_cnt,
    ucs.latest_comment_date,
    uvs.upvotes_given,
    uvs.downvotes_given,
    uvs.favorites_given,
    COALESCE(p.title,'[No Recent Post]')            AS latest_post_title,
    COALESCE(p.tags,'')                             AS latest_post_tags,
    /* count how many <code> blocks the latest post contains */
    (LENGTH(COALESCE(p.body,'')) -
     LENGTH(REPLACE(COALESCE(p.body,''),'<code>',''))) / LENGTH('<code>') AS code_snippet_cnt
FROM   RankedUsers ru
LEFT JOIN UserBadgeCounts    ub  ON ub.userid = ru.id
LEFT JOIN UserPostStats      ups ON ups.userid = ru.id
LEFT JOIN UserCommentStats   ucs ON ucs.userid = ru.id
LEFT JOIN UserVoteStats      uvs ON uvs.userid = ru.id
LEFT JOIN posts               p  ON p.id = ups.latest_post_id
WHERE  ru.score_rank <= 100
  AND  ru.location IS NOT NULL
  AND  ru.location <> ''
ORDER BY ru.score_rank
UNION ALL
SELECT
    u.id,
    u.displayname,
    0                         AS total_badges,
    0                         AS total_score,
    NULL                      AS score_rank,
    NULL                      AS loc_rank,
    CASE WHEN u.emailhash IS NULL THEN 'NO_EMAIL' ELSE 'HAS_EMAIL' END AS email_flag,
    0                         AS gold_badges,
    0                         AS silver_badges,
    0                         AS bronze_badges,
    0                         AS question_cnt,
    0                         AS answer_cnt,
    NULL                      AS latest_post_date,
    0                         AS comment_cnt,
    NULL                      AS latest_comment_date,
    0                         AS upvotes_given,
    0                         AS downvotes_given,
    0                         AS favorites_given,
    NULL                      AS latest_post_title,
    ''                        AS latest_post_tags,
    0                         AS code_snippet_cnt
FROM   users u
WHERE  NOT EXISTS (SELECT 1 FROM posts p WHERE p.owneruserid = u.id)
  AND  u.reputation < 100
ORDER BY total_score DESC NULLS LAST
LIMIT 200;
