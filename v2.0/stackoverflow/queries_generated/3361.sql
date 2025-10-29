-- {"query": "3361.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2720} 

WITH
    -- Aggregate user‑level post statistics
    user_posts AS (
        SELECT
            u.id                                   AS user_id,
            u.displayname,
            u.reputation,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1)               AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2)               AS answer_cnt,
            AVG(p.score) FILTER (WHERE p.posttypeid = 1)              AS avg_q_score,
            AVG(p.score) FILTER (WHERE p.posttypeid = 2)              AS avg_a_score,
            MAX(p.lastactivitydate)                                   AS last_activity
        FROM users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    -- Badge points per user (gold=3, silver=2, bronze=1)
    user_badges AS (
        SELECT
            b.userid,
            SUM(CASE b.class WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 1 END) AS badge_points,
            COUNT(*) FILTER (WHERE b.tagbased = 1)                 AS tag_badge_cnt,
            COUNT(*) FILTER (WHERE b.tagbased = 0)                 AS named_badge_cnt,
            MAX(b.date)                                            AS last_badge_date
        FROM badges b
        GROUP BY b.userid
    ),

    -- Net vote score and favourite count per post, then rolled up to user
    post_votes AS (
        SELECT
            v.postid,
            p.owneruserid                                     AS owner_id,
            SUM(CASE v.votetypeid WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS net_score,
            COUNT(*) FILTER (WHERE v.votetypeid = 5)                         AS fav_cnt
        FROM votes v
        JOIN posts p ON p.id = v.postid
        GROUP BY v.postid, p.owneruserid
    ),
    user_votes AS (
        SELECT
            pv.owner_id AS user_id,
            SUM(pv.net_score)      AS total_net_score,
            SUM(pv.fav_cnt)        AS total_fav_cnt
        FROM post_votes pv
        GROUP BY pv.owner_id
    ),

    -- Tag usage per user (questions only), rank tags per user
    tag_usage AS (
        SELECT
            u.id                                          AS user_id,
            t.tagname,
            COUNT(*)                                      AS tag_post_cnt,
            ROW_NUMBER() OVER (PARTITION BY u.id ORDER BY COUNT(*) DESC) AS tag_rank
        FROM users u
        JOIN posts p ON p.owneruserid = u.id AND p.posttypeid = 1
        CROSS JOIN LATERAL regexp_split_to_table(p.tags, '[><]+') AS traw(tagtxt)
        JOIN tags t ON t.tagname = traw.tagtxt
        GROUP BY u.id, t.tagname
    ),
    top_tags AS (
        SELECT
            user_id,
            STRING_AGG(tagname, ', ' ORDER BY tag_rank) AS top_3_tags
        FROM tag_usage
        WHERE tag_rank <= 3
        GROUP BY user_id
    )

SELECT
    up.user_id,
    up.displayname,
    up.reputation,
    up.question_cnt,
    up.answer_cnt,
    COALESCE(up.avg_q_score,0)::numeric(5,2)      AS avg_q_score,
    COALESCE(up.avg_a_score,0)::numeric(5,2)      AS avg_a_score,
    COALESCE(ub.badge_points,0)                   AS badge_points,
    COALESCE(uv.total_net_score,0)                AS net_score,
    COALESCE(uv.total_fav_cnt,0)                  AS fav_votes,
    COALESCE(tt.top_3_tags,'')                    AS top_tags,
    up.last_activity,
    ub.last_badge_date,
    CASE
        WHEN up.reputation > 20000 THEN 'Veteran'
        WHEN up.reputation > 5000  THEN 'Experienced'
        WHEN up.reputation > 1000 THEN 'Intermediate'
        ELSE 'Newbie'
    END                                          AS reputation_tier,
    ROW_NUMBER() OVER (ORDER BY up.reputation DESC)           AS reputation_rank,
    RANK()       OVER (ORDER BY COALESCE(uv.total_net_score,0) + COALESCE(ub.badge_points,0) DESC) AS influence_rank
FROM user_posts up
LEFT JOIN user_badges ub ON ub.userid = up.user_id
LEFT JOIN user_votes uv ON uv.user_id = up.user_id
LEFT JOIN top_tags tt   ON tt.user_id = up.user_id
WHERE up.question_cnt > 0 OR up.answer_cnt > 0

UNION ALL

-- Aggregated totals row
SELECT
    NULL,
    '--- Aggregated Totals ---',
    SUM(up.reputation)                         AS reputation,
    SUM(up.question_cnt)                       AS question_cnt,
    SUM(up.answer_cnt)                         AS answer_cnt,
    AVG(up.avg_q_score)                        AS avg_q_score,
    AVG(up.avg_a_score)                        AS avg_a_score,
    SUM(COALESCE(ub.badge_points,0))           AS badge_points,
    SUM(COALESCE(uv.total_net_score,0))        AS net_score,
    SUM(COALESCE(uv.total_fav_cnt,0))          AS fav_votes,
    NULL,
    MAX(up.last_activity),
    MAX(ub.last_badge_date),
    NULL,
    NULL,
    NULL
FROM user_posts up
LEFT JOIN user_badges ub ON ub.userid = up.user_id
LEFT JOIN user_votes uv ON uv.user_id = up.user_id
WHERE up.reputation > 0

EXCEPT
SELECT *
FROM (SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL) AS dummy
ORDER BY reputation_rank NULLS LAST, influence_rank NULLS LAST;
