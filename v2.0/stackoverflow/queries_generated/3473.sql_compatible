WITH
    user_stats AS (
        SELECT
            u.id                                    AS user_id,
            u.displayname                           AS display_name,
            u.reputation,
            COALESCE(u.upvotes,0) - COALESCE(u.downvotes,0) AS net_votes,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges,
            (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS question_cnt,
            (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS answer_cnt,
            (SELECT COUNT(*) FROM comments c WHERE c.userid = u.id)                 AS comment_cnt
        FROM users u
        WHERE u.reputation > 0
    ),

    ranked_users AS (
        SELECT
            us.*,
            ROW_NUMBER() OVER (ORDER BY us.reputation DESC, us.net_votes DESC) AS rank_overall
        FROM user_stats us
        WHERE (us.gold_badges + us.silver_badges + us.bronze_badges) > 0
    ),

    tag_metrics AS (
        SELECT
            t.id                                   AS tag_id,
            t.tagname,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_posts,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_posts,
            SUM(COALESCE(p.score,0))               AS total_score,
            STRING_AGG(DISTINCT u.displayname, ', ')
                FILTER (WHERE u.id IS NOT NULL)   AS active_owners
        FROM tags t
        LEFT JOIN posts p
               ON p.tags LIKE ('%<' || t.tagname || '>%')
        LEFT JOIN users u
               ON u.id = p.owneruserid
        GROUP BY t.id, t.tagname
        HAVING COUNT(p.id) > 10
    ),

    recent_closes AS (
        SELECT
            ph.postid,
            MAX(CASE WHEN ph.posthistorytypeid = 10 THEN ph.comment END) AS close_reason_id,
            MAX(ph.creationdate)                                          AS closed_on
        FROM posthistory ph
        WHERE ph.posthistorytypeid = 10
        GROUP BY ph.postid
    ),

    combined AS (
        SELECT
            ru.user_id,
            ru.display_name,
            ru.reputation,
            ru.net_votes,
            ru.gold_badges,
            ru.silver_badges,
            ru.bronze_badges,
            ru.question_cnt,
            ru.answer_cnt,
            ru.comment_cnt,
            COALESCE(CAST(rc.close_reason_id AS VARCHAR), '0')        AS last_close_reason,
            rc.closed_on,
            COALESCE(tm.total_score,0)                     AS top_tag_score,
            tm.tagname,
            ROW_NUMBER() OVER (PARTITION BY ru.user_id ORDER BY tm.total_score DESC) AS tag_rank
        FROM ranked_users ru
        LEFT JOIN LATERAL (
            SELECT p.id
            FROM posts p
            WHERE p.owneruserid = ru.user_id
            ORDER BY p.creationdate DESC
            LIMIT 1
        ) latest_post ON TRUE
        LEFT JOIN recent_closes rc
               ON rc.postid = latest_post.id
        LEFT JOIN LATERAL (
            SELECT tm2.*
            FROM tag_metrics tm2
            JOIN posts p2
                 ON p2.tags LIKE ('%<' || tm2.tagname || '>%')
            WHERE p2.owneruserid = ru.user_id
            ORDER BY tm2.question_posts DESC
            LIMIT 1
        ) tm ON TRUE
    )

SELECT
    c.user_id,
    c.display_name,
    c.reputation,
    c.net_votes,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.question_cnt,
    c.answer_cnt,
    c.comment_cnt,
    c.last_close_reason,
    c.closed_on,
    c.top_tag_score,
    c.tagname,
    c.tag_rank
FROM combined c
WHERE c.tag_rank = 1

UNION ALL

SELECT
    ru.user_id,
    ru.display_name,
    ru.reputation,
    ru.net_votes,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.question_cnt,
    ru.answer_cnt,
    ru.comment_cnt,
    'N/A'                AS last_close_reason,
    CAST(NULL AS TIMESTAMP)                 AS closed_on,
    0                    AS top_tag_score,
    NULL                 AS tagname,
    NULL                 AS tag_rank
FROM ranked_users ru
WHERE ru.rank_overall <= 5

EXCEPT

SELECT
    c.user_id,
    c.display_name,
    c.reputation,
    c.net_votes,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.question_cnt,
    c.answer_cnt,
    c.comment_cnt,
    c.last_close_reason,
    c.closed_on,
    c.top_tag_score,
    c.tagname,
    c.tag_rank
FROM combined c
WHERE c.top_tag_score = 0

ORDER BY reputation DESC, net_votes DESC
LIMIT 100;